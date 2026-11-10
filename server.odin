package main

import "core:fmt"
import "core:net"

LOCAL_IP :: "127.0.0.1"
LOCAL_PORT :: 8080

main :: proc() {
	local_addr := net.parse_address(LOCAL_IP)
	assert(local_addr != nil, "Failed to parse local address")

	endpoint := net.Endpoint {
		address = local_addr,
		port = LOCAL_PORT
	}

	socket, err_init := net.listen_tcp(endpoint)
	defer net.close(socket)

	assert(err_init == nil, "Failed to create listener socket")
	
	fmt.printfln("Listening on %s:%d", LOCAL_IP, LOCAL_PORT)

	for {
		client, _, err_accept := net.accept_tcp(socket)
		defer net.close(client)
		
		if err_accept != nil {
			fmt.eprintln("Failed to accept client", err_accept)
			continue
		}

		buffer: [256]byte
		for {
			bytes_recv, err_recv := net.recv_tcp(client, buffer[:])
			if err_recv != nil {
				fmt.eprintln("Failed to receive data")
				break
			}
			if bytes_recv == 0 {
				fmt.println("Disconnecting client...")
				break
			}

			received := buffer[:bytes_recv]
			fmt.printfln("Server received [ %d bytes ]: %s", bytes_recv, received)

			bytes_sent, err_sent := net.send_tcp(client, received)
			if err_sent != nil {
				fmt.eprintln("Failed to send data")
				break
			}
			sent := received[:bytes_sent]
			fmt.printfln("Server sent [ %d bytes ]: %s", bytes_sent, sent)
		}
	}
}
