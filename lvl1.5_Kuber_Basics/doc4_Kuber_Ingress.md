Ingress in Kubernetes is an API object that manages external access to the services in a cluster, typically HTTP/HTTPS. It provides load balancing, SSL termination, and name-based virtual hosting.

What Ingress Manages:
Ingress manages these objects and functions:

1. Routes External Traffic to Services
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
2. Manages Multiple Hosts/Virtual Hosts
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-host-ingress
spec:
  rules:
  - host: app1.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app1-service
            port:
              number: 80
  - host: app2.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
3. Handles TLS/SSL Termination
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: tls-secret
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
Objects That RECONCILE Ingress (Ingress Controllers):
Ingress doesn't work alone - it needs an Ingress Controller to reconcile and implement the rules:

1. Nginx Ingress Controller
yaml
# Deploys nginx pods that watch for Ingress objects
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-ingress-controller
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-ingress
  template:
    metadata:
      labels:
        app: nginx-ingress
    spec:
      containers:
      - name: nginx
        image: nginx/nginx-ingress:latest
        args:
        - /nginx-ingress-controller
        - --publish-service=$(POD_NAMESPACE)/nginx-ingress
2. Traefik Ingress Controller
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: traefik-ingress-controller
spec:
  template:
    spec:
      containers:
      - name: traefik
        image: traefik:v2.9
        args:
        - --api
        - --providers.kubernetesingress
3. AWS ALB Ingress Controller
yaml
# Creates AWS Application Load Balancer
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-alb-ingress-controller
spec:
  template:
    spec:
      containers:
      - name: alb-ingress-controller
        image: amazon/aws-alb-ingress-controller:v1.1.9
        args:
        - --cluster-name=my-cluster
        - --aws-vpc-id=vpc-123456
        - --aws-region=us-west-2
4. Istio Gateway (Service Mesh)
yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: my-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
When to Use Ingress:
Use Case 1: Multiple Services Under One Domain
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-based-ingress
spec:
  rules:
  - host: mydomain.com
    http:
      paths:
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
      - path: /admin
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 3000
Use Case 2: SSL/TLS Termination
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ssl-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - secure.example.com
    secretName: tls-certificate
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-app
            port:
              number: 443
Use Case 3: Load Balancing with Annotations
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: load-balanced-ingress
  annotations:
    nginx.ingress.kubernetes.io/load-balance: "ewma"
    nginx.ingress.kubernetes.io/upstream-hash-by: "$remote_addr"
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app-service
            port:
              number: 80
Use Case 4: Rate Limiting
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rate-limited-ingress
  annotations:
    nginx.ingress.kubernetes.io/limit-rps: "100"
    nginx.ingress.kubernetes.io/limit-burst: "200"
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
Ingress vs Other Networking Objects:
Object	Purpose	Layer	Use Case
Ingress	HTTP/HTTPS routing	L7	Web traffic, path-based routing
Service	Internal load balancing	L4	Internal service discovery
LoadBalancer	External direct access	L4	Non-HTTP services
NodePort	External access via node IP	L4	Development, testing
Complete Example:
1. Deploy Application
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 80
2. Create TLS Secret
bash
kubectl create secret tls tls-secret \
  --cert=path/to/cert.crt \
  --key=path/to/cert.key
3. Define Ingress
yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: tls-secret
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
When NOT to Use Ingress:
Non-HTTP traffic (use LoadBalancer/NodePort)

TCP/UDP services (databases, custom protocols)

Simple single-service applications

When you need L4 load balancing features

In Summary:
Ingress is Kubernetes' way of managing external HTTP/HTTPS traffic to your cluster. It's like a smart traffic director that routes requests based on hostnames and paths to the appropriate services, while handling SSL termination and load balancing.

Ingress Controller is the actual software that implements the Ingress rules, while Ingress Resource is the configuration that tells the controller what to do.