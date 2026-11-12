package tcp

import "core:fmt"
import "core:net"
import "core:strings"

LOCAL_IP :: "127.0.0.1"
LOCAL_PORT :: 8080

main :: proc() {
	listen()
}

listen :: proc(ip := LOCAL_IP, port := LOCAL_PORT) {
	local_addr := net.parse_address(ip)
	if local_addr == nil {
		fmt.eprintln("Failed to parse local address")
		return
	}

	endpoint := net.Endpoint {
		address = local_addr,
		port    = port,
	}

	socket, err_init := net.listen_tcp(endpoint)
	if err_init != nil {
		fmt.eprintln("Failed to create listener socket", err_init)
		return
	}
	defer net.close(socket)

	fmt.printfln("Listening on %s:%d", ip, port)

	for {
		client, _, err_accept := net.accept_tcp(socket)
		if err_accept != nil {
			fmt.eprintln("Failed to accept client", err_accept)
			continue
		}
		defer net.close(client)

		buffer: [256]byte
		builder: strings.Builder
		strings.builder_init(&builder)
		defer strings.builder_destroy(&builder)

		for {
			num_recv, err_recv := net.recv_tcp(client, buffer[:])
			if err_recv != nil {
				fmt.eprintln("Failed to receive data", err_recv)
				return
			}
			if num_recv == 0 {
				fmt.println("Disconnecting client...")
				break
			}

			bytes_recv := buffer[:num_recv]
			strings.write_bytes(&builder, bytes_recv)
			fmt.printfln("Server received [ %d bytes ]: %s", num_recv, bytes_recv)

			num_sent, err_sent := net.send_tcp(client, bytes_recv)
			if err_sent != nil {
				fmt.eprintln("Failed to send data", err_sent)
				return
			}
			sent_bytes := bytes_recv[:num_sent]
			fmt.printfln("Server sent [ %d bytes ]: %s", num_sent, sent_bytes)

			if num_recv == 0 || (num_recv == 2 && bytes_recv[num_recv - 1] == '\n') {
				break
			}
		}

		fmt.println("[FULL TRANSMISSION]\n", strings.to_string(builder), "\n[END TRANSMISSION]")
	}
}
