package http

import "core:fmt"
import "core:net"
import "core:strconv"
import "core:strings"

LOCAL_ENDPOINT :: "127.0.0.1:80"

Http_Get :: struct {
	resource: string,
}
Http_Post :: struct {
	resource:       string,
	content_length: int,
	payload:        string,
}
Http_Request :: union {
	Http_Get,
	Http_Post,
}

Http_Response :: struct {
	status:         Http_Status,
	content_length: int,
	payload:        string,
}

receive_headers :: proc(client: net.TCP_Socket, string_builder: ^strings.Builder) -> (ok: bool) {
	buffer: [256]byte
	for {
		num_recv, err_recv := net.recv_tcp(client, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Couldn't receive from client:", err_recv)
			return false
		}
		if num_recv <= 0 do break

		bytes_recv := buffer[:num_recv]
		strings.write_bytes(string_builder, bytes_recv)

		if strings.contains(strings.to_string(string_builder^), "\r\n\r\n") {
			break
		}
	}
	return true
}

parse_headers :: proc(headers_str: string) -> Http_Request {
	if len(headers_str) == 0 do return nil
	temp := strings.split(headers_str, "\r\n\r\n") // in case of some of the body comes around
	if len(temp) == 0 do return nil

	method: string
	resource: string
	content_length: int

	headers := strings.split(temp[0], "\r\n")
	if len(headers) == 0 do return nil

	header := headers[0]
	method_resource := strings.split(header, " ")
	if len(method_resource) != 3 {
		fmt.eprintln("[BAD REQUEST] Malformed header")
		return nil
	}

	method = strings.to_lower(method_resource[0])
	resource = method_resource[1]

	if method == "get" {
		return Http_Get{resource = resource}
	} else if method != "post" {
		fmt.eprintln("[Method Not Allowed]", method)
		return nil
	}

	for header, i in headers[1:] {
		key, _, value := strings.partition(header, ":")
		key = strings.to_lower(key)


		if key == "content-length" {
			content_len, parse_ok := strconv.parse_int(strings.trim_space(value), 10)
			content_length = content_len
			if !parse_ok {
				fmt.eprintln("[BAD REQUEST] Invalid content-length type:", value)
				return nil
			}
		}
	}

	if method == "post" {
		if content_length == 0 {
			fmt.eprintln("[BAD REQUEST] Content-length is zero")
			return nil
		}
		return Http_Post{resource = resource, content_length = content_length}
	}
	return nil
}

main :: proc() {
	endpoint, parsed_endpoint := net.parse_endpoint(LOCAL_ENDPOINT)
	if !parsed_endpoint {
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

		buffer: [256]byte
		request_builder := strings.builder_make(context.temp_allocator)

		if !receive_headers(client, &request_builder) do continue //TODO: implement timeout

		headers_str := strings.to_string(request_builder)

		request := parse_headers(headers_str)
		if request == nil do continue

		// GET PAYLOAD AND CHECK AGAINST CONTENT-LENGTH
		#partial switch &r in request {
		case Http_Post:
			payload_bytes := 0
			possible_body := strings.split(headers_str, "\r\n\r\n")
			if len(possible_body) == 2 {
				payload_bytes += len(possible_body[1])
			}
			for payload_bytes < r.content_length {
				num_recv, err_recv := net.recv_tcp(client, buffer[:])
				if err_recv != nil {
					fmt.eprintln("Couldn't receive body data", err_recv)
					break
				}
				if num_recv <= 0 do break
				bytes_recv := buffer[:num_recv]
				strings.write_bytes(&request_builder, bytes_recv)
				payload_bytes += num_recv
			}

			if payload_bytes != r.content_length {
				fmt.eprintln("[BAD REQUEST] Content-length differs from payload's size")
				continue
			}

			latest_request_str := strings.to_string(request_builder)
			header_payload := strings.split(latest_request_str, "\r\n\r\n")
			payload_str := header_payload[1]
			r.payload = payload_str
		}

		fmt.println(request)
		// header, _, payload := strings.partition(request, "\r\n\r\n")

		// SEND RESPONSE
		response_builder := strings.builder_make(context.temp_allocator)
		response_status := "HTTP/1.1 200 OK\r\n"
		response_delimiter := "\r\n\r\n"
		response_payload := "Hello from server!!"
		content_length := fmt.tprintf("Content-Length: %d\r\n", len(response_payload))

		strings.write_string(&response_builder, response_status)
		strings.write_string(&response_builder, content_length)
		strings.write_string(&response_builder, response_delimiter)
		strings.write_string(&response_builder, response_payload)
		response := transmute([]byte)strings.to_string(response_builder)

		num_send, err_send := net.send_tcp(client, response)
		if err_send != nil {
			fmt.eprintln("Couldn't serve response:", err_send)
			continue
		}
		fmt.println("[SENT]", string(response[:num_send]))
	}
}
