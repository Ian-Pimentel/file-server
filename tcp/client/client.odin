package client

import "core:fmt"
import "core:net"
import "core:os"

LOCAL_IP :: "127.0.0.1"
LOCAL_PORT :: 8080

main :: proc() {
	send_multiple_messages()
}

send_multiple_messages :: proc(ip := LOCAL_IP, port := LOCAL_PORT) {
	local_addr := net.parse_address(ip)
	if local_addr == nil {
		fmt.eprintln("Failed to parse local address")
		return
	}

	endpoint := net.Endpoint {
		address = local_addr,
		port    = port,
	}

	socket, err := net.dial_tcp(endpoint)
	if err != nil {
		fmt.eprintln("Couldn't connect to server:", err)
		return
	}
	defer net.close(socket)

	buffer: [256]byte
	for {
		num_read, err_read := os.read(os.stdin, buffer[:])
		if err_read != nil {
			if err_read != .EOF do fmt.eprintln("Error reading stdin:", err_read)
			return
		}
		bytes_read := buffer[:num_read]

		if num_read == 0 || (num_read == 2 && bytes_read[num_read - 1] == '\n') {
			fmt.println("No message sent.")
			continue
		}

		num_sent, err_sent := net.send_tcp(socket, bytes_read)
		if err_sent != nil {
			fmt.eprintln("Failed to send data", err_sent)
			return
		}

		fmt.printfln("Client sent [ %d bytes ]: %s", num_sent, bytes_read[:num_sent])

		num_recv, err_recv := net.recv_tcp(socket, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Failed to receive data", err_recv)
			return
		}
		bytes_recv := buffer[:num_recv]

		fmt.printfln("Client received [ %d bytes ]: %s", num_recv, bytes_recv)
	}
}

send_message :: proc(ip := LOCAL_IP, port := LOCAL_PORT, message: string) {
	if len(message) == 0 {
		fmt.println("No message sent.")
		return
	}

	local_addr := net.parse_address(ip)
	if local_addr == nil {
		fmt.eprintln("Failed to parse local address")
		return
	}

	endpoint := net.Endpoint {
		address = local_addr,
		port    = port,
	}

	socket, err := net.dial_tcp(endpoint)
	if err != nil {
		fmt.eprintln("Couldn't connect to server:", err)
		return
	}
	defer net.close(socket)

	data := transmute([]byte)message
	total_data_sent := 0
	for total_data_sent < len(data) {
		remaining_data := data[total_data_sent:]
		num_sent, err_sent := net.send_tcp(socket, remaining_data)
		if err_sent != nil {
			fmt.eprintln("Failed to send data", err_sent)
			return
		}

		bytes_sent := remaining_data[:num_sent]
		fmt.printfln("Client sent [ %d bytes ]: %s", num_sent, string(bytes_sent))

		total_data_sent += num_sent
	}

	buffer: [256]byte
	for {
		num_recv, err_recv := net.recv_tcp(socket, buffer[:])
		if err_recv != nil {
			fmt.eprintln("Failed to receive data", err_recv)
			break
		}
		if num_recv == 0 {
			break
		}

		bytes_recv := buffer[:num_recv]
		fmt.printfln("Client received [ %d bytes ]: %s", num_recv, string(bytes_recv))
	}
}
