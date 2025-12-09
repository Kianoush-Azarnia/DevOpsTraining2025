OSI Model Layers in Kubernetes Networking:
Layer 4 (Transport Layer)
TCP/UDP protocols

Works with: IP addresses and ports

What it sees: Just raw data streams

Examples in Kubernetes: Services, LoadBalancer, NodePort

yaml
# L4 Service - only cares about IP:PORT
apiVersion: v1
kind: Service
metadata:
  name: database-service
spec:
  selector:
    app: database
  ports:
  - protocol: TCP
    port: 5432        # Service port
    targetPort: 5432  # Pod port
  type: LoadBalancer  # Operates at L4
Layer 7 (Application Layer)
HTTP/HTTPS protocols

Works with: URLs, hostnames, headers, cookies

What it sees: Actual application data (HTTP requests)

Examples in Kubernetes: Ingress, Istio Gateways

yaml
# L7 Ingress - understands HTTP semantics
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  rules:
  - host: app.example.com        # L7 - Host header
    http:
      paths:
      - path: /api/v1            # L7 - URL path
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /static            # L7 - URL path  
        pathType: Prefix
        backend:
          service:
            name: static-service
            port:
              number: 80
Complete OSI Model Context:
Layer	Name	What It Handles	Kubernetes Examples
L7	Application	HTTP, HTTPS, DNS, SMTP	Ingress, Istio, API Gateways
L6	Presentation	Encryption, compression	TLS termination in Ingress
L5	Session	Connection management	Persistent sessions in Ingress
L4	Transport	TCP, UDP, ports, flow control	Services, LoadBalancer, NodePort
L3	Network	IP addresses, routing	CNI plugins, kube-proxy, Pod networking
L2	Data Link	MAC addresses, switches	Node networking, bridge interfaces
L1	Physical	Cables, signals	Physical servers, network cards
Detailed Comparison:
Layer 4 (Transport Layer) Characteristics:
yaml
# L4 Service Example
apiVersion: v1
kind: Service
metadata:
  name: tcp-service
spec:
  type: LoadBalancer
  selector:
    app: game-server
  ports:
  - name: tcp
    protocol: TCP
    port: 25565           # External port
    targetPort: 25565     # Pod port
### This service:
 - Only sees: IP packets on port 25565
 - Doesn't care: What data is being sent
 - Can't route based on: HTTP headers, URLs, hostnames
# L4 Load Balancing:

Round-robin based on IP:PORT

No understanding of application content

Works for any TCP/UDP protocol (databases, games, custom protocols)

## Layer 7 (Application Layer) Characteristics:
yaml
# L7 Ingress Example
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: http-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
  - host: myapp.com
    http:
      paths:
      - path: /v1(/|$)(.*)    # L7 - URL path matching
        pathType: Prefix
        backend:
          service:
            name: v1-api
            port:
              number: 8080
      - path: /v2(/|$)(.*)    # L7 - URL path matching
        pathType: Prefix
        backend:
          service:
            name: v2-api
            port:
              number: 8080
## L7 Load Balancing:

Routes based on HTTP headers, URLs, cookies

Can perform SSL termination

Understands application semantics

Content-aware routing

Practical Examples by Protocol:
Database (L4 - TCP)
yaml
# PostgreSQL - L4 only needed
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
## No Ingress needed - databases speak TCP, not HTTP
Web API (L7 - HTTP)
yaml
## Web API needs L7 routing
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-ingress
spec:
  rules:
  - host: api.company.com
    http:
      paths:
      - path: /users
        pathType: Prefix
        backend:
          service:
            name: user-service
            port:
              number: 8080
      - path: /orders
        pathType: Prefix
        backend:
          service:
            name: order-service
            port:
              number: 8080
Mixed Protocol Application:
yaml
## Web frontend (L7)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: web-service
            port: 80

---
## Database (L4)
apiVersion: v1
kind: Service
metadata:
  name: db-service
spec:
  type: ClusterIP
  ports:
  - port: 5432
    targetPort: 5432
  selector:
    app: database

---
## Redis cache (L4)
apiVersion: v1
kind: Service
metadata:
  name: redis-service
spec:
  type: ClusterIP
  ports:
  - port: 6379
    targetPort: 6379
  selector:
    app: redis
Performance Considerations:
L4 Advantages:
Faster - less processing overhead

Protocol agnostic - works with any TCP/UDP

Simpler - less configuration

L7 Advantages:
Smarter routing - based on content

SSL termination - offloads encryption

Advanced features - rate limiting, rewrites, authentication

When to Use Each:
Use Case	Recommended Layer	Why
Websites/APIs	L7 (Ingress)	Path-based routing, SSL, headers
Databases	L4 (Service)	TCP protocol, no HTTP semantics
gRPC services	L7 (Ingress)	HTTP/2, header-based routing
Game servers	L4 (LoadBalancer)	Custom TCP/UDP protocols
File transfer	L4 (Service)	FTP, SFTP protocols
Microservices	L7 (Ingress)	API gateway pattern
In Summary:
L4 (Layer 4) in Kubernetes deals with TCP/UDP connections at the transport level - it's like a postal service that only cares about addresses (IP:PORT), not the letter content.

L7 (Layer 7) deals with application protocols like HTTP - it's like a mail sorter that reads the addresses AND can route based on the letter content (URLs, headers, etc.).

This distinction explains why we use Services for database connections (L4) and Ingress for web traffic (L7)!
