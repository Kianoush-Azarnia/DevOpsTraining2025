# Kubernetes Basics
We gonna see what these concepts are about:
- Pod
- Deployment
- Service 
- Secret
- PVC

## Pods
A Pod is the smallest and simplest deployable unit in Kubernetes. Let me explain it in simple terms:

### Pod = The Basic "Wrapper" for Your Containers
Think of a Pod as a wrapper or logical host for one or more containers.

### Key Characteristics:
#### 1. One or More Containers
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app-pod
spec:
  containers:
  - name: nginx-container
    image: nginx:latest
  - name: helper-container
    image: busybox:latest
    command: ['sh', '-c', 'echo "I am a helper"']
```
- A Pod can run multiple containers that work together
- Containers in the same Pod share resources and network

#### 2. Shared Resources
Containers in the same Pod share:

- Network: Same IP address, localhost, ports
- Storage: Same volumes and storage
- Memory/CPU: Same resource limits

#### 3. Ephemeral Nature
- Pods are mortal - they get created, live, and die
- If a Pod dies, it's gone forever (Kubernetes creates new ones)
- Each Pod gets a unique IP address

### Common Pod Patterns:
#### Single Container Pod (Most Common)
- ~80% of cases:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
  - name: nginx
    image: nginx:1.19
    ports:
    - containerPort: 80
```
#### Multi-Container Pod (Sidecar Pattern)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-with-log-shipper
spec:
  containers:
  - name: web-app
    image: my-web-app:latest
    ports:
    - containerPort: 8080
  - name: log-shipper
    image: fluentd:latest
    # Fluentd collects logs from web-app
```

### Real-World Analogies:
#### 🚗 Car Analogy:
- Container = Engine, Transmission, Wheels (individual components)
- Pod = The entire car with all components working together
- Kubernetes = The entire transportation system managing all cars

#### 🏢 Office Analogy:
- Container = Individual employee with specific skills
- Pod = A team working together in the same room
- Kubernetes = The office manager assigning teams to projects

### Why Pods? (Instead of Just Containers)
#### Before Pods (Docker alone):
```bash
# Manually managing related containers
docker run --name web nginx
docker run --name log-collector fluentd
docker network connect web log-collector
# Complex to manage relationships!
```

#### With Pods (Kubernetes):
```yaml
# One unit - Kubernetes handles the relationships
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: web
    image: nginx
  - name: log-collector
    image: fluentd
# They automatically share network and storage!
```

### Pod Lifecycle:
```text
Created → Pending → Running → Succeeded/Failed → Deleted
```

### Practical Examples:
#### View Pods:
```bash
kubectl get pods
kubectl get pods -o wide
kubectl describe pod my-pod
```

#### Create a Pod:
```bash
kubectl run my-pod --image=nginx:latest
```

#### Delete a Pod:
``` bash
kubectl delete pod my-pod
```

### Important Notes:
1. You rarely create Pods directly - use Deployments, StatefulSets, etc.
2. Pods are disposable - if they fail, Kubernetes replaces them
3. Each Pod is isolated from other Pods
4. Pods don't self-heal - that's why we use higher-level controllers

### When to Use Multi-Container Pods:
- **Sidecar**: Log collection, monitoring, proxies
- **Adapter**: Format conversion, data transformation
- **Ambassador**: Network proxy, service mesh
- **Init containers**: Setup tasks before main app starts

### In Summary:
> A Pod is Kubernetes' way of saying: "These containers belong together and should be treated as a single unit for scheduling, networking, and storage purposes."
It's the fundamental building block that makes container orchestration practical and scalable!

## **Deployment = Application Manager**

A **Deployment** is a Kubernetes object that manages the deployment and scaling of your application Pods. It's like an **automated manager** for your application lifecycle.

### **Deployment = Pod Manager + Update Coordinator**

Think of it like:
- **Pods** = Individual workers
- **Deployment** = The manager that hires, fires, and coordinates workers
- **ReplicaSet** = The supervisor that ensures the right number of workers

### **What Deployments Do:**

#### **1. Declarative Updates**
You declare **what you want**, and the Deployment figures out **how to get there**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3        # I want 3 copies running
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.20
        ports:
        - containerPort: 80
```

#### **2. Rolling Updates (Zero Downtime)**
```bash
# Update to new version smoothly
kubectl set image deployment/my-app nginx=nginx:1.21

# What happens:
# 1. Creates new Pods with v1.21
# 2. Waits for them to be ready
# 3. Gradually terminates old Pods (v1.20)
# 4. No downtime during update!
```

#### **3. Automatic Rollback**
```bash
# If something goes wrong, rollback automatically
kubectl rollout undo deployment/my-app

# Or to a specific revision
kubectl rollout history deployment/my-app
kubectl rollout undo deployment/my-app --to-revision=2
```

### **Deployment Structure:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
spec:
  replicas: 3                    # How many Pod copies
  selector:                      # How to find Pods to manage
    matchLabels:
      app: web-app
  template:                      # Pod template
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.20
        ports:
        - containerPort: 80
  strategy:                      # Update strategy
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1               # How many extra Pods during update
      maxUnavailable: 0         # How many Pods can be unavailable
```

### **Real-World Analogies:**

#### **🏢 Restaurant Kitchen:**
- **Pods** = Individual cooks
- **Deployment** = Head chef managing the kitchen
- **Update** = Changing recipes without closing the restaurant

#### **🚗 Taxi Fleet:**
- **Pods** = Individual taxis
- **Deployment** = Fleet manager
- **Scaling** = Adding/removing taxis based on demand
- **Updates** = Replacing old taxis with new models gradually

#### **🎬 Movie Theater:**
- **Pods** = Individual movie projectors
- **Deployment** = Theater manager
- **Update** = Switching from film to digital projectors without stopping shows

### **Key Features:**

#### **1. Self-Healing**
```bash
# If a Pod dies, Deployment creates a new one automatically
kubectl delete pod web-app-xyz123
# Deployment automatically creates web-app-abc456 to replace it
```

#### **2. Scaling**
```bash
# Scale up for more traffic
kubectl scale deployment web-app --replicas=5

# Scale down to save resources
kubectl scale deployment web-app --replicas=2
```

#### **3. Version Management**
```bash
# See rollout history
kubectl rollout history deployment/web-app

# See current status
kubectl rollout status deployment/web-app
```

### **Practical Examples:**

#### **Basic Web Application:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.20
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

#### **Database-Aware Application:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: my-api:latest
        env:
        - name: DATABASE_URL
          value: "postgresql://user:pass@db:5432/mydb"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
```

### **Deployment vs Other Objects:**

| Object | Purpose | When to Use |
|--------|---------|-------------|
| **Pod** | Single instance | Testing, one-off tasks |
| **ReplicaSet** | Multiple copies | Simple scaling (no updates) |
| **Deployment** | Managed app lifecycle | **Most common** - web apps, APIs |
| **StatefulSet** | Stateful apps | Databases, ordered deployment |
| **DaemonSet** | Every node | Log collectors, monitoring |

### **Common Deployment Strategies:**

#### **Rolling Update (Default)**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%        # Can have 25% extra Pods during update
    maxUnavailable: 25%  # 25% of Pods can be unavailable
```
- **Best for**: Most web applications
- **Advantage**: Zero downtime

#### **Recreate**
```yaml
strategy:
  type: Recreate
```
- **Best for**: Development, when brief downtime is OK
- **How it works**: Kill all old Pods, then start new ones

### **Working with Deployments:**

#### **Create and Manage:**
```bash
# Create from YAML
kubectl apply -f deployment.yaml

# Get deployments
kubectl get deployments
kubectl get deploy  # Short version

# See details
kubectl describe deployment my-app

# See Pods created by deployment
kubectl get pods -l app=my-app
```

#### **Updates and Rollbacks:**
```bash
# Update image
kubectl set image deployment/my-app nginx=nginx:1.21

# Scale
kubectl scale deployment/my-app --replicas=5

# Rollback
kubectl rollout undo deployment/my-app

# Check status
kubectl rollout status deployment/my-app
```

### **Why Use Deployments?**

1. **Declarative**: Describe what you want, not how to do it
2. **Automated**: Kubernetes handles the complex rollout process
3. **Reliable**: Self-healing, automatic rollback
4. **Scalable**: Easy to scale up/down
5. **Zero Downtime**: Rolling updates ensure continuous service

### **In Summary:**

> A **Deployment** is Kubernetes' way of managing stateless applications. It's your "application manager" that handles deployment, scaling, updates, and rollbacks automatically. You declare your desired state, and the Deployment makes it happen while keeping your application available.

**95% of your applications in Kubernetes will use Deployments** - they're the workhorse for managing containerized applications!

## Service

A **Service** in Kubernetes is a stable network endpoint that provides reliable access to a set of Pods. It's like a **load balancer** or **network proxy** that sits in front of your Pods.

### **The Problem Services Solve:**

**Without Services:**
- Pods are ephemeral (they come and go)
- Pod IP addresses change when they restart
- How do other applications find your Pods?
- How do you load balance traffic?

**With Services:**
- Stable IP address and DNS name
- Automatic load balancing
- Survives Pod restarts/replacements

### **Service = Permanent Front Door to Your Pods**

Think of it like:
- **Pods** = Restaurant kitchen staff (come and go, change shifts)
- **Service** = Host stand at restaurant entrance (always there, directs customers)

### **Service Types:**

#### **1. ClusterIP (Default) - Internal Service**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-internal-service
spec:
  selector:
    app: my-app
  ports:
    - port: 80        # Service port
      targetPort: 8080 # Pod port
  type: ClusterIP
```
- **Use case**: Communication between microservices inside the cluster
- **Accessible only** within the Kubernetes cluster
- **Gets a stable IP** that other Pods can use

#### **2. NodePort - External Access on Node IP**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-nodeport-service
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30007  # External port (30000-32767)
  type: NodePort
```
- **Use case**: External access to your application
- **Makes service accessible** on each Node's IP at the NodePort
- **Access via**: `http://<any-node-ip>:30007`

#### **3. LoadBalancer - Cloud Provider Load Balancer**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-loadbalancer-service
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
  type: LoadBalancer
```
- **Use case**: External access with cloud load balancer
- **Cloud provider** creates an external load balancer
- **Gets a public IP** automatically (AWS ELB, GCP Load Balancer, etc.)

#### **4. ExternalName - DNS Alias**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-external-service
spec:
  type: ExternalName
  externalName: api.external-company.com
```
- **Use case**: Proxy to external services
- **Creates a DNS alias** inside your cluster
- **No selectors or Pods** - just redirects to external service

### **How Services Work:**

#### **Selector-Based Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  selector:
    app: web-server    # Matches Pods with label app=web-server
    tier: frontend     # Matches Pods with label tier=frontend
  ports:
    - port: 80
      targetPort: 8080
```

**Kubernetes automatically:**
1. **Finds all Pods** with labels `app=web-server` and `tier=frontend`
2. **Creates endpoints** for those Pods
3. **Load balances** traffic across all matching Pods
4. **Updates automatically** when Pods are added/removed

### **Real-World Analogies:**

#### **🏢 Office Building:**
- **Pods** = Individual meeting rooms (numbers can change)
- **Service** = Reception desk (always at the same number, directs you to available rooms)

#### **📞 Call Center:**
- **Pods** = Call center agents (some may be on break, new ones join)
- **Service** = PBX phone system (routes calls to available agents)

#### **🍽️ Restaurant:**
- **Pods** = Cooks in the kitchen (change shifts, some busy)
- **Service** = Food expo window (consolidates orders from all cooks)

### **Practical Examples:**

#### **View Services:**
```bash
kubectl get services
kubectl get svc  # Short version

# See details
kubectl describe service my-service
```

#### **Accessing Services:**

**From inside cluster:**
```bash
# Using Service name (DNS)
curl http://my-service:80

# Using ClusterIP
curl http://10.96.123.456:80
```

**From outside (NodePort):**
```bash
# Access via any node's IP
curl http://<node-ip>:30007
```

#### **Service Discovery:**
```bash
# DNS resolution inside cluster
nslookup my-service

# Kubernetes creates DNS entries like:
# my-service.namespace.svc.cluster.local
```

### **Service vs Pod Relationship:**

```yaml
# Pod with labels
apiVersion: v1
kind: Pod
metadata:
  name: web-pod-1
  labels:
    app: webapp      # ← Service looks for this label
    tier: frontend   # ← and this label
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 8080

# Service that selects those Pods
apiVersion: v1
kind: Service
metadata:
  name: web-service
spec:
  selector:
    app: webapp      # ← Matches Pods with this label
    tier: frontend   # ← Matches Pods with this label
  ports:
    - port: 80
      targetPort: 8080
```

### **Common Patterns:**

#### **Microservices Communication:**
```bash
# Service A talks to Service B
curl http://service-b:80/api/data

# Instead of hardcoding Pod IPs that change!
```

#### **Web Application:**
```
Internet → LoadBalancer Service → Multiple Web Pods
```

#### **Database Access:**
```
App Pods → Database Service → Database Pods
```

### **Key Benefits:**

1. **Stable IP/DNS** - Never changes, even when Pods restart
2. **Load Balancing** - Distributes traffic across healthy Pods
3. **Service Discovery** - Automatic finding of backend Pods
4. **Decoupling** - Frontend doesn't need to know about Pod changes
5. **Health Checking** - Only routes to healthy Pods

### **In Summary:**

> A **Service** is Kubernetes' way of providing a stable network identity and load balancing for your dynamic, ephemeral Pods. It's the "glue" that holds your microservices together and makes them reliably accessible.

Without Services, you'd have to manually track Pod IP addresses and implement your own load balancing - Services automate all of this!

## Secret
A **Secret** in Kubernetes is an object that stores sensitive information like passwords, API keys, tokens, and SSH keys. It's a secure way to manage credentials without hardcoding them in your Pod definitions.

### **What Secrets Store:**

- 🔑 **Passwords** (database, API, application)
- 🔐 **TLS certificates** (SSL/TLS keys)
- 🎫 **API tokens** (OAuth, JWT, service accounts)
- 🔑 **SSH keys** (for git operations, remote access)
- 📝 **Configuration files** with sensitive data

### **Secret = Secure Credential Storage**

Think of it like:
- **Pods** = Your applications that need credentials
- **Secrets** = A secure vault that provides credentials safely
- **Kubernetes** = The security system managing access

### **Types of Secrets:**

#### **1. Opaque (Generic) - Most Common**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-db-secret
type: Opaque
data:
  username: dXNlcm5hbWU=        # base64 encoded "username"
  password: cGFzc3dvcmQ=        # base64 encoded "password"
```

#### **2. docker-registry - For Private Container Registries**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-registry-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-docker-config>
```

#### **3. tls - For TLS Certificates**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-tls-secret
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-private-key>
```

#### **4. bootstrap-token - For Node Bootstrap**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: bootstrap-token-abc123
type: bootstrap.kubernetes.io/token
data:
  token-id: YWJjMTIz
  token-secret: ZGVmNDU2
```

### **Creating Secrets:**

#### **Method 1: kubectl create secret (Easiest)**
```bash
# From literal values
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=secret123

# From files
kubectl create secret generic tls-secret \
  --from-file=tls.crt=./cert.crt \
  --from-file=tls.key=./cert.key

# From environment file
echo -n "admin" > ./username.txt
echo -n "secret123" > ./password.txt
kubectl create secret generic db-secret \
  --from-file=./username.txt \
  --from-file=./password.txt
```

#### **Method 2: YAML Manifest (Base64 Encoded)**
```bash
# First, base64 encode your data
echo -n "admin" | base64
# Output: YWRtaW4=

echo -n "secret123" | base64  
# Output: c2VjcmV0MTIz
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-db-secret
type: Opaque
data:
  username: YWRtaW4=
  password: c2VjcmV0MTIz
```

### **Using Secrets in Pods:**

#### **Method 1: Environment Variables**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app-pod
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: DB_USERNAME
      valueFrom:
        secretKeyRef:
          name: my-db-secret
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: my-db-secret
          key: password
```

#### **Method 2: Volume Mount (Files)**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app-pod
spec:
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: secret-volume
      mountPath: "/etc/secrets"
      readOnly: true
  volumes:
  - name: secret-volume
    secret:
      secretName: my-db-secret
      # Creates files: /etc/secrets/username, /etc/secrets/password
```

#### **Method 3: Pull Images from Private Registry**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-app-pod
spec:
  containers:
  - name: app
    image: private.registry.com/my-app:latest
  imagePullSecrets:
  - name: my-registry-secret
```

### **Real-World Analogies:**

#### **🏦 Bank Vault:**
- **Secrets** = Safety deposit boxes with your valuables
- **Pods** = You (need temporary access to valuables)
- **Kubernetes** = Bank security system

#### **🔐 Hotel Safe:**
- **Secrets** = In-room safes with your passport/cash
- **Pods** = Hotel guests (need secure storage)
- **Kubernetes** = Hotel management system

#### **🎫 Concert Tickets:**
- **Secrets** = Digital tickets with QR codes
- **Pods** = Phone apps that display tickets
- **Kubernetes** = Ticket distribution system

### **Security Features:**

#### **1. Base64 Encoding (Not Encryption!)**
```bash
# Secrets are base64 encoded, NOT encrypted
echo "YWRtaW4=" | base64 --decode
# Output: admin
```

#### **2. Etcd Encryption (Optional)**
```yaml
# Enable encryption at rest in kube-apiserver
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-encoded-32-byte-key>
```

#### **3. RBAC Protection**
```yaml
# Control who can access secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "watch", "list"]
```

### **Practical Examples:**

#### **View Secrets:**
```bash
kubectl get secrets
kubectl describe secret my-db-secret

# See the actual data (base64 decoded)
kubectl get secret my-db-secret -o jsonpath='{.data.username}' | base64 --decode
```

#### **MySQL Database Pod with Secrets:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  root-password: cm9vdHBhc3M=  # "rootpass" base64 encoded
  database: bXlhcHA=           # "myapp" base64 encoded
---
apiVersion: v1
kind: Pod
metadata:
  name: mysql-pod
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    env:
    - name: MYSQL_ROOT_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mysql-secret
          key: root-password
    - name: MYSQL_DATABASE
      valueFrom:
        secretKeyRef:
          name: mysql-secret
          key: database
```

#### **TLS Termination with Secrets:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
type: kubernetes.io/tls
data:
  tls.crt: <base64-cert>
  tls.key: <base64-key>
---
apiVersion: v1
kind: Pod
metadata:
  name: nginx-tls-pod
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: tls-volume
      mountPath: "/etc/nginx/ssl"
  volumes:
  - name: tls-volume
    secret:
      secretName: tls-secret
```

### **Best Practices:**

#### **1. Don't Commit Secrets to Git**
```bash
# Use .gitignore
echo "*-secret.yaml" >> .gitignore

# Or use tools like:
- Helm Secrets
- Sealed Secrets
- External Secret Operators (AWS Secrets Manager, HashiCorp Vault)
```

#### **2. Use Short-Lived Secrets**
```bash
# Rotate secrets regularly
kubectl delete secret old-secret
kubectl create secret generic new-secret ...
```

#### **3. Limit Access with RBAC**
```yaml
# Only allow specific service accounts to read secrets
```

### **Secret vs ConfigMap:**

| Aspect | Secret | ConfigMap |
|--------|---------|------------|
| **Data** | Sensitive | Non-sensitive |
| **Encoding** | Base64 | Plain text |
| **Use case** | Passwords, keys | Configuration files |
| **Security** | Additional protections | Basic protections |

### **In Summary:**

> A **Secret** is Kubernetes' secure way to manage sensitive information, providing a layer of abstraction and security between your credentials and your applications. It's like a digital safe that your Pods can access without ever seeing the actual combination.

Secrets help you follow security best practices by keeping credentials out of your code, container images, and version control!

## PVC
A **PVC (Persistent Volume Claim)** in Kubernetes is a request for storage by a user. It's like a "storage ticket" that Pods use to get persistent storage.

### **PVC = Storage Request Ticket**

Think of it like:
- **Storage** = A parking lot with spaces
- **PV (Persistent Volume)** = An actual parking space
- **PVC (Persistent Volume Claim)** = A parking ticket that gives you the right to use a space
- **Pod** = The car that needs parking

### **The Storage Problem PVC Solves:**

**Without PVCs:**
- Developers need to know about specific storage details
- Hard to manage storage across different environments
- Storage configuration tied to specific infrastructure

**With PVCs:**
- Developers just request storage (size, type)
- Kubernetes handles the underlying storage details
- Portable across different clusters and cloud providers

### **The PVC-PV-Pod Relationship:**

```
Pod → PVC (Claim) → PV (Volume) → Actual Storage (Disk, Cloud Storage, etc.)
```

### **How It Works:**

#### **1. Administrator Creates Storage (PV)**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  hostPath:
    path: /data/my-pv
```

#### **2. Developer Requests Storage (PVC)**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: fast-ssd
```

#### **3. Pod Uses the Claim**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app-pod
spec:
  containers:
  - name: app
    image: my-app:latest
    volumeMounts:
    - name: storage-volume
      mountPath: /data
  volumes:
  - name: storage-volume
    persistentVolumeClaim:
      claimName: my-pvc
```

### **PVC Access Modes:**

#### **ReadWriteOnce (RWO)**
- Read-write by a single node
- **Use case**: Database, single Pod applications
```yaml
accessModes:
  - ReadWriteOnce
```

#### **ReadOnlyMany (ROX)**
- Read-only by many nodes
- **Use case**: Configuration files, static content
```yaml
accessModes:
  - ReadOnlyMany
```

#### **ReadWriteMany (RWX)**
- Read-write by many nodes
- **Use case**: Shared file systems, user uploads
```yaml
accessModes:
  - ReadWriteMany
```

### **Real-World Analogies:**

#### **🏢 Office Space:**
- **Actual Storage** = Office building with rooms
- **PV** = A specific office room
- **PVC** = Your office rental agreement
- **Pod** = Your company that needs office space

#### **🚗 Car Rental:**
- **Actual Storage** = Rental car fleet
- **PV** = A specific car
- **PVC** = Your rental reservation
- **Pod** = You needing a car

#### **💾 USB Drive:**
- **Actual Storage** = Various USB drives available
- **PV** = A specific 64GB USB drive
- **PVC** = Your request for "any 32GB+ USB drive"
- **Pod** = Your laptop that needs storage

### **Dynamic Provisioning (Most Common):**

Instead of manually creating PVs, use **Storage Classes** for automatic provisioning:

#### **1. Define Storage Class**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  fsType: ext4
```

#### **2. Create PVC (Automatically creates PV)**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: fast-ssd  # Triggers dynamic provisioning
```

#### **3. Use in Pod**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-server
spec:
  containers:
  - name: nginx
    image: nginx:latest
    volumeMounts:
    - name: web-storage
      mountPath: /usr/share/nginx/html
  volumes:
  - name: web-storage
    persistentVolumeClaim:
      claimName: dynamic-pvc
```

### **Practical Examples:**

#### **View PVCs and PVs:**
```bash
kubectl get pvc
kubectl get pv
kubectl describe pvc my-pvc
```

#### **MySQL Database with Persistent Storage:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard
---
apiVersion: v1
kind: Pod
metadata:
  name: mysql-pod
spec:
  containers:
  - name: mysql
    image: mysql:8.0
    env:
    - name: MYSQL_ROOT_PASSWORD
      value: "password"
    volumeMounts:
    - name: mysql-storage
      mountPath: /var/lib/mysql
  volumes:
  - name: mysql-storage
    persistentVolumeClaim:
      claimName: mysql-pvc
```

#### **WordPress with Multiple PVCs:**
```yaml
# Database PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-db-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
# WordPress files PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-files-pvc
spec:
  accessModes:
    - ReadWriteMany  # Multiple pods might need access
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: wordpress
spec:
  containers:
  - name: wordpress
    image: wordpress:latest
    volumeMounts:
    - name: wp-files
      mountPath: /var/www/html
  volumes:
  - name: wp-files
    persistentVolumeClaim:
      claimName: wordpress-files-pvc
```

### **Storage Classes (Cloud Examples):**

#### **AWS EBS**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-gp3
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
  fsType: ext4
```

#### **Google Cloud Persistent Disk**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcp-ssd
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
```

#### **Azure Disk**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-ssd
provisioner: kubernetes.io/azure-disk
parameters:
  storageaccounttype: Premium_LRS
  kind: Managed
```

### **PVC Lifecycle States:**

```
Pending → Bound → Released
```

- **Pending**: Waiting for a matching PV
- **Bound**: Successfully bound to a PV
- **Released**: PVC deleted, but PV not yet reclaimed

### **Reclaim Policies:**

#### **Retain**
- Keeps PV and data after PVC deletion
- **Use case**: Critical data, manual cleanup needed
```yaml
persistentVolumeReclaimPolicy: Retain
```

#### **Delete**
- Automatically deletes PV and underlying storage
- **Use case**: Temporary data, development
```yaml
persistentVolumeReclaimPolicy: Delete
```

#### **Recycle** (Deprecated)
- Deletes data and makes PV available for new claims

### **Benefits of PVCs:**

1. **Abstraction**: Developers don't need storage details
2. **Portability**: Same PVC works across different environments
3. **Dynamic Provisioning**: Storage created automatically on-demand
4. **Quota Management**: Control storage usage per namespace
5. **Lifecycle Management**: Automated cleanup and retention

### **Common Use Cases:**

- **Databases**: MySQL, PostgreSQL, MongoDB
- **File Storage**: User uploads, shared documents
- **Log Storage**: Application logs, audit trails
- **Backup Storage**: Database backups, snapshots
- **Content Management**: WordPress, Drupal files

### **In Summary:**

> A **PVC** is Kubernetes' way of abstracting storage details from application developers. It's like a "storage reservation" that says "I need this much storage with these features" without worrying about where it comes from or how it's implemented.

PVCs make storage in Kubernetes as easy and portable as running containers themselves!