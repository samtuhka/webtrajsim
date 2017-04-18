#sudo npm install -g ws-tcp-bridge ws-tcp-bridge
#ws-tcp-bridge --method=ws2tcp --lport=8080 --rhost=127.0.0.1:8081

import socket

serversocket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
serversocket.bind(('localhost', 8081))
serversocket.listen(5) # become a server socket, maximum 5 connections

while True:
    connection, address = serversocket.accept()
    buf = connection.recv(64)
    if len(buf) > 0:
        print buf
        break
