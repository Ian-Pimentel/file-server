package main

import "core:os"
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

	socket, err := net.dial_tcp(endpoint)
	defer net.close(socket)

	if err != nil {
		fmt.eprintln("Couldn't connect to server", err)
	}

	buffer: [256]byte
	for {
		num_read, err_read := os.read(os.stdin, buffer[:])
		if err_read != nil {
			if err_read != .EOF do fmt.eprintln("Error reading stdin", err_read)
			break
		}

		if num_read == 0 {
			fmt.println("No message sent.")
			break
		}

		bytes_read := buffer[:num_read]

		num_sent, err_sent := net.send_tcp(socket, bytes_read)
		if err_sent != nil {
			fmt.eprintln("Failed to send data", err_sent)
			break
		}

		fmt.printfln("Client sent [ %d bytes ]: %s", num_sent, bytes_read[:num_sent])

		num_recv, err_recv := net.recv_tcp(socket, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Failed to receive data", err_recv)
			break
		}
		bytes_recv := buffer[:num_recv]

		fmt.printfln("Client received [ %d bytes ]: %s", num_recv, bytes_recv)
	}
}
