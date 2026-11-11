package main

import "core:fmt"
import "core:net"

LOCAL_IP :: "127.0.0.1"
LOCAL_PORT :: 8080

main :: proc() {
	local_addr := net.parse_address(LOCAL_IP)
	if local_addr == nil {
  		fmt.eprintln("Failed to parse local address")
    	return
	}

	endpoint := net.Endpoint {
		address = local_addr,
		port = LOCAL_PORT
	}

	socket, err_init := net.listen_tcp(endpoint)
	defer net.close(socket)

	if err_init != nil { 
		fmt.eprintln("Failed to create listener socket", err_init)
		return
	}
	
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
			num_recv, err_recv := net.recv_tcp(client, buffer[:])
			if err_recv != nil {
				fmt.eprintln("Failed to receive data", err_recv)
				break
			}
			if num_recv == 0 {
				fmt.println("Disconnecting client...")
				break
			}

			bytes_recv := buffer[:num_recv]
			fmt.printfln("Server received [ %d bytes ]: %s", num_recv, bytes_recv)

			num_sent, err_sent := net.send_tcp(client, bytes_recv)
			if err_sent != nil {
				fmt.eprintln("Failed to send data", err_sent)
				break
			}
			sent_bytes := bytes_recv[:num_sent]
			fmt.printfln("Server sent [ %d bytes ]: %s", num_sent, sent_bytes)
		}
	}
}
