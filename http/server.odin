package http

import "core:fmt"
import "core:net"
import "core:strings"

LOCAL_ENDPOINT :: "127.0.0.1:80"

main :: proc() {
	endpoint, parsed_endpoint := net.parse_endpoint(LOCAL_ENDPOINT)
	if !parsed_endpoint {
		fmt.eprintln("Couldn't parse endpoint:", LOCAL_ENDPOINT)
		return
	}
	socket, err_listen := net.listen_tcp(endpoint)
	if err_listen != nil {
		fmt.eprintln("Couldn't listen to socket:", err_listen)
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
		sb := strings.builder_make_none(context.temp_allocator)
		//RECEIVE HEADERS
		for {
			num_recv, err_recv := net.recv_tcp(client, buffer[:])
			if err_recv != nil {
				fmt.eprintln("Couldn't receive from client:", err_recv)
				break
			}

			bytes_recv := buffer[:num_recv]
			strings.write_bytes(&sb, bytes_recv)

			if strings.contains(strings.to_string(sb), "\r\n\r\n") {
				break
			}
		}
		request := strings.to_string(sb)
		fmt.println("[RECEIVED]", request)
		// header, _, body := strings.partition(request, "\r\n\r\n")

		//SEND RESPONSE
		response_builder := strings.builder_make_none(context.temp_allocator)
		response_status := "HTTP/1.1 200 OK\r\n"
		response_delimiter := "\r\n\r\n"
		response_body := "Hello from server!!"
		content_length := fmt.tprintf("Content-Length: %d\r\n", len(response_body))
		
		strings.write_string(&response_builder, response_status)
		strings.write_string(&response_builder, content_length)
		strings.write_string(&response_builder, response_delimiter)
		strings.write_string(&response_builder, response_body)
		response := transmute([]byte)strings.to_string(response_builder)
		
		num_send, err_send := net.send_tcp(client, response)
		if err_send != nil {
			fmt.eprintln("Couldn't serve response:", err_send)
			continue
		}
		fmt.println("[SENT]", string(response[:num_send]))
	}
}
