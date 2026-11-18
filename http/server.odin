package http

import "core:fmt"
import "core:net"
import "core:reflect"
import "core:strconv"
import "core:strings"

BUFFER_SIZE :: 256
LOCAL_ENDPOINT :: "127.0.0.1:80"

Http_Status :: enum {
	// 2XX
	OK                     = 200,
	Created                = 201,
	No_Content             = 204,
	// 4XX
	Bad_Request            = 400,
	Unauthorized           = 401,
	Not_Found              = 404,
	Method_Not_Allowed     = 405,
	Request_Timeout        = 408,
	Length_Required        = 411,
	content_Too_Large      = 413,
	URI_Too_Long           = 414,
	Unsupported_Media_Type = 415,
	// Unprocessable_Content           = 422,
	Too_Many_Requests      = 429,
	// 5XX
	Internal_Server_Error  = 500,
	Not_Implemented        = 501,
	Insufficient_Storage   = 507,
}

Http_Method :: enum {
	GET,
	POST,
	PUT,
	DELETE,
}

header_fields :: map[string]string
Http_Request :: struct {
	method:  Http_Method,
	uri:     string,
	headers: header_fields,
	content: string,
}

Http_Response :: struct {
	status:  Http_Status,
	content: string,
}

receive_header :: proc(client: net.TCP_Socket, string_builder: ^strings.Builder) -> (ok: bool) {
	buffer: [BUFFER_SIZE]byte
	for {
		num_recv, err_recv := net.recv_tcp(client, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Couldn't receive from client:", err_recv)
			return false
		}
		if num_recv <= 0 do break

		bytes_recv := buffer[:num_recv]
		strings.write_bytes(string_builder, bytes_recv)

		if strings.contains(strings.to_string(string_builder^), "\r\n\r\n") do break
	}
	return true
}

parse_header :: proc(
	header_str: string,
) -> (
	method: Http_Method,
	uri: string,
	headers: header_fields,
	ok: bool,
) {
	if len(header_str) <= 0 {
		fmt.eprintln("[BAD REQUEST] Malformed header")
		return
	}

	header_iter := header_str

	request_resource, resource_ok := strings.split_iterator(&header_iter, "\r\n")
	if !resource_ok {
		fmt.eprintln("[BAD REQUEST] Malformed header")
		return
	}

	method_str, method_ok := strings.split_iterator(&request_resource, " ")
	temp_uri, uri_ok := strings.split_iterator(&request_resource, " ")

	// TODO: parse uri
	if !(method_ok || uri_ok) {
		fmt.eprintln("[BAD REQUEST] Malformed header")
		return
	}

	temp_method, ok_parse_method := reflect.enum_from_name(Http_Method, method_str)
	if !ok_parse_method {
		fmt.eprintln("[Method Not Allowed]", method_str)
		return
	}

	headers = make(header_fields)
	for header_field in strings.split_iterator(&header_iter, "\r\n") {
		if len(header_field) == 0 do break // empty line separating header and content

		key, sep, val := strings.partition(header_field, ":")
		if sep == "" {
			delete(headers)
			fmt.eprintln("[BAD REQUEST] Invalid header field:", header_field)
			return
		}
		key = strings.to_lower(strings.trim_space(key), context.temp_allocator)
		val = strings.to_lower(strings.trim_space(val), context.temp_allocator)

		if key in headers {
			delete(headers)
			fmt.eprintln("[BAD REQUEST] Duplicated fields:", header_field)
			return
		}

		headers[key] = val
	}

	if !("content-length" in headers) {
		delete(headers)
		fmt.eprintln("[Length_Required] Couldn't find Content-length")
		return
	} else {
		value := headers["content-length"]
		_, parse_ok := strconv.parse_int(value, 10)
		if !parse_ok {
			delete(headers)
			fmt.eprintln("[BAD REQUEST] Invalid content-length type:", value)
			return
		}
	}

	return temp_method, temp_uri, headers, true
}

receive_content :: proc(
	client: net.TCP_Socket,
	string_builder: ^strings.Builder,
	content_length: int,
) -> (
	ok: bool,
) {
	buffer: [BUFFER_SIZE]byte
	content_bytes := 0
	for content_bytes < content_length {
		num_recv, err_recv := net.recv_tcp(client, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Couldn't receive content data", err_recv)
			return false
		}
		if num_recv <= 0 do break

		bytes_recv := buffer[:num_recv]
		strings.write_bytes(string_builder, bytes_recv)
		content_bytes += num_recv
	}
	return true
}

send_response :: proc(response: Http_Response, client: net.TCP_Socket) -> (ok: bool) {
	response_builder := strings.builder_make()
	defer strings.builder_destroy(&response_builder)

	status_name, was_alloc := strings.replace_all(reflect.enum_string(response.status), "_", " ")
	defer if was_alloc do delete(status_name)

	fmt.sbprintf(&response_builder, "HTTP/1.1 %d %s\r\n", response.status, status_name)
	fmt.sbprintf(&response_builder, "Content-Length: %d\r\n", len(response.content))
	fmt.sbprintf(&response_builder, "Content-Type: text/plain\r\n")
	fmt.sbprintf(&response_builder, "Connection: close\r\n")
	fmt.sbprint(&response_builder, "\r\n")
	fmt.sbprint(&response_builder, response.content)

	response := transmute([]byte)strings.to_string(response_builder)
	bytes_sent := 0
	for bytes_sent < len(response) {
		num_send, err_send := net.send_tcp(client, response[bytes_sent:])
		if err_send != nil {
			fmt.eprintln("Couldn't serve response:", err_send)
			return false
		}
		bytes_sent += num_send
	}
	fmt.printfln("[SENT]\n%s", string(response))
	return true
}

// TODO: reuse same string builder
main :: proc() {
	endpoint, ok_endpoint := net.parse_endpoint(LOCAL_ENDPOINT)
	if !ok_endpoint {
		fmt.eprintln("Couldn't parse endpoint:", endpoint)
		return
	}

	socket, err_listen := net.listen_tcp(endpoint)
	if err_listen != nil {
		fmt.eprintln("Couldn't listen to socket:", err_listen)
		return
	}
	defer net.close(socket)

	fmt.println("Listening at", net.to_string(endpoint))

	for {
		client, _, err_accept := net.accept_tcp(socket)
		if err_accept != nil {
			fmt.eprintln("Couldn't connect to client:", err_accept)
			continue
		}
		defer net.close(client)

		defer free_all(context.temp_allocator) // TODO: implement client arena/allocator

		buffer: [BUFFER_SIZE]byte
		request_builder := strings.builder_make()
		defer strings.builder_destroy(&request_builder)

		if !receive_header(client, &request_builder) do continue //TODO: implement timeout

		request_str := strings.to_string(request_builder)
		end_header_index := strings.index(request_str, "\r\n\r\n")

		response: Http_Response

		// TODO: receive early http error codes
		// OR pass a fucking pointer to a control boolean around and send_response() on the spot
		method, uri, headers, ok_parse_headers := parse_header(request_str[:end_header_index])
		if !ok_parse_headers do continue
		// kinda mind frying that I need to take care this lives as long as the deps need it.
		// deleting the request struct after, doesn't delete it. LEARN. ABOUT. ARENAS.
		defer delete(headers)

		content_length, _ := strconv.parse_int(headers["content-length"], 10)

		content_str := request_str[end_header_index + 4:]
		if content_length > 0 && len(content_str) < content_length {
			if !receive_content(client, &request_builder, content_length - len(content_str)) do continue
		}

		request_str = strings.to_string(request_builder)
		content_str = request_str[end_header_index + 4:]

		if len(content_str) != content_length {
			send_response(
				{.status = .Bad_Request, .content = "Content-length mismatch with content's size"},
				client,
			)
			// fmt.eprintln("[BAD REQUEST] Content-length mismatch with content's size")
			continue
		}

		request := Http_Request {
			method  = method,
			uri     = uri,
			headers = headers,
			content = content_str,
		}

		fmt.println(request)

		response := Http_Response {
			status  = .OK,
			content = "Hello from server!",
		}

		if !send_response(response, client) do continue

	}
}
