Explaination of each item at the deep level using AI: 
- start with the high-level Kubernetes object idea
- show how Kubernetes implements it 
    - which controllers/components are involved
    - the control-plane flow
    - what system calls / Linux objects it ends up creating
    - where to look for logs/state. 
- In a concrete and pragmatic way so we can translate them into real OS-level troubleshooting.

# 0 — Quick checklist: Kubernetes objects (list only)

Use these one-liners when asked “what is X?” so you can start:

* Pod
* Service
* Deployment
* ReplicaSet
* StatefulSet
* DaemonSet
* Job / CronJob
* ConfigMap
* Secret
* PersistentVolume (PV)
* PersistentVolumeClaim (PVC)
* StorageClass
* Namespace
* Node
* Ingress
* Endpoint / EndpointSlice
* ClusterRole / Role / RoleBinding / ClusterRoleBinding
* HorizontalPodAutoscaler (HPA)
* CustomResourceDefinition (CRD)
* APIService
* AdmissionReview / ValidatingWebhookConfiguration / MutatingWebhookConfiguration
* PodDisruptionBudget (PDB)
* ServiceAccount
* NetworkPolicy

With “X is a Kubernetes object that …” and then dive into the deep mapping below.

---

# 1 — What is a Node?

**Short:** A Node is a worker machine in Kubernetes (VM or physical) that runs pods.
**System-level view / final reality:** a Node is a Linux host (processes & files) with kubelet (a process), container runtime (containerd, runc), CNI plugin processes, systemd unit(s), and various directories under `/var/lib/kubelet`, `/var/run`, `/etc/kubernetes`. The Node’s “Kubernetes identity” is mostly metadata in the API server backed by etcd, but at runtime the real work happens in host-level processes, network namespaces, cgroups, and files.

**Components & responsibilities (high level):**

* `kubelet` (process on the node): watches the API server for pods assigned to this node, creates containers via CRI, mounts volumes, manages pod lifecycle, reports status to API server.
* Container runtime (containerd + runc): implements containers as Linux processes using namespaces and cgroups.
* CNI plugin (bridge, calico/flip/flannel): sets up pod networking (veth pairs, veth<>bridge, routes, iptables rules).
* kube-proxy (daemon on node or as pod): implements Services (iptables/ipvs rules or userspace proxy).
* kubelet volume plugin/CNI/CIFS drivers/CSI/other drivers: interact with kernel and disk.

**What gets created on Linux when a pod is scheduled to a node:**

* Processes (container processes) — `runc` spawns real processes inside namespaces. Each container is one or multiple processes seen by the kernel.
* Namespaces (PID, NET, MNT, IPC, UTS, user): Linux kernel namespaces isolate the container from the host.
* cgroups: the container runtime places the container's processes in cgroups for resource limiting and accounting.
* Files and mountpoints: volumes are mounted into container mount namespaces (bind mounts, FUSE, block device mounts).
* Network objects: veth pair, a peer in a bridge or a macvlan; routes; iptables / nftables rules; network namespace directory under `/proc/<pid>/ns/net`.
* Files under `/var/lib/kubelet/pods/<podUID>` with pod-related volume data, pod manifests, containers’ log files (often under `/var/log/pods` or `/var/log/containers`).

**Where to look / commands:**

* `kubectl get nodes` / `kubectl describe node <node>` (API layer)
* On node: `systemctl status kubelet` / `journalctl -u kubelet -f`
* Running containers: `crictl ps` or `ctr -n k8s.io containers list` / `docker ps` (if docker)
* Pod files: `/var/lib/kubelet/pods/` and `/var/log/pods/` (or container runtime logs)
* Network: `ip netns`, `ip link`, `brctl show`, `iptables -t nat -L -n -v` or `ipvsadm -Ln` (if ipvs mode)

---

# 2 — Control plane components (2.a, 2.b, 2.c, 2.d)

## 2.a — What are the main components of the control plane?

* **kube-apiserver** — the API endpoint, the single source of truth entry point (reads/writes to etcd).
* **etcd** — the persistent key-value store for cluster state (usually runs on control-plane nodes).
* **kube-controller-manager** — a process that runs many controllers (replication, endpoints, namespace controller, service accounts...) or multiple controller manager processes; watches API and reconciles desired state.
* **kube-scheduler** — decides which Node a newly created unscheduled pod should run on.
* **cloud-controller-manager** — integrates cluster with cloud provider APIs (external load balancers, route management, node lifecycle, etc.) — present in cloud environments.
* **addon controllers / aggregated APIs** — e.g., CRD controllers/operators running as pods.
* **kube-proxy** (not always in control plane; runs on nodes) — implements Service networking.

## 2.b — Responsibilities of each one (concise & relevant)

* **kube-apiserver**

  * Authoritative HTTP/REST API for cluster resources.
  * Validates and admits requests (admission controllers).
  * Writes/reads state to/from etcd (or aggregated APIs).
  * Serves kubectl, controllers, kubelets, operators.
  * Produces audit logs when configured.

* **etcd**

  * Durable storage of all API objects’ states (the “truth”).
  * Handles transactions and versioning; strong consistency is important.
  * Real-world: etcd is a process that stores files on disk (rocksdb/bolt) — so disk, file descriptors, and I/O are the kernel-level realities.

* **kube-controller-manager**

  * Runs control loops for many core controllers (Node controller, ReplicationController, Deployment controllers via ReplicaSet, Service Account & Token controllers, PersistentVolume controllers, Endpoint controllers, etc.).
  * Each controller watches resources in the API, computes diffs between desired & actual, then executes actions by talking to API server (which leads to kubelet actions via watch events).

* **kube-scheduler**

  * Runs scheduling algorithm: filters nodes, scores them, picks a node, updates Pod spec with `.spec.nodeName`.
  * Also runs as a process, communicates via the API.

* **cloud-controller-manager**

  * Talks to cloud provider APIs (create load balancers, manage routes, attach volumes).
  * Uses controllers like Service/Node/Route that perform cloud-specific work.

## 2.c — How to read logs of each component

There are two typical deployments: control-plane components as static pods (kubeadm style) or systemd-managed processes. How you read logs depends on that.

**If components run as static pods (common with kubeadm):**

* Control plane static pod manifests live at `/etc/kubernetes/manifests/` on control-plane nodes. The kubelet runs them as pods; container runtime runs them.
* Use `kubectl -n kube-system get pods` to list pods (e.g., `kube-apiserver-<node>`).
* Use `kubectl -n kube-system logs kube-apiserver-<node>` (or `kubectl logs -n kube-system <pod> -c <container>`) to view logs.
* On host, container runtime logs or journal: `docker logs` / `ctr` / `journalctl -u kubelet`.

**If components run as systemd units (older or custom setups):**

* `systemctl status kube-apiserver` and `journalctl -u kube-apiserver -f`.
* `journalctl -u kube-controller-manager -f`, `journalctl -u kube-scheduler -f`, `journalctl -u etcd -f`.

**etcd logs:**

* If etcd is a pod: `kubectl -n kube-system logs etcd-<node>`. If systemd: `journalctl -u etcd -f`.
* etcd stores raft logs/data under `/var/lib/etcd` — those are files on disk.

**kube-controller-manager & kube-scheduler:**

* `kubectl -n kube-system logs kube-controller-manager-<node>`
* `kubectl -n kube-system logs kube-scheduler-<node>`

**kubelet:**

* `journalctl -u kubelet -f` or check `/var/log/syslog` depending on distro.

## 2.d — Which pods contain the audit log?

* **Audit logs are produced by the kube-apiserver**. The apiserver writes audit events based on `--audit-policy-file` and `--audit-log-path`. So the kube-apiserver process (or pod) is the source of audit logs.
* **Where the logs actually reside depends on setup:**

  * If apiserver is a static pod: its container stdout/err can be read with `kubectl logs -n kube-system kube-apiserver-<node>`; the audit log may be written to a file inside the apiserver container filesystem (if `--audit-log-path` points to a file path), which might be mounted to the host (e.g., hostPath) so the file is accessible on the host under `/var/log/kubernetes/audit.log` or similar.
  * In many managed clusters, a logging agent (fluentd, filebeat) or a sidecar/daemonset collects apiserver logs and ships them elsewhere.
* **Summary:** the apiserver (pod/process) produces audit records — where they end up (file on host, stdout, external system) depends on `--audit-log-path` and your logging configuration.

---

# 3 — What is the “controller” concept in Kubernetes?

**High-level:** A controller is a control loop — a process that watches the cluster state (via the API) and takes actions to move the current state toward the desired state declared in objects. “Controller” is the pattern; the implementation is a program/process.

**How it works (flow):**

1. Controller watches resources (List + Watch) from the apiserver (etcd).
2. When an object changes (or periodically), controller reconciles: reads desired state from the object’s spec and actual state (from API or node metrics).
3. Controller issues changes by updating resources via the API (create/delete/update). For example, ReplicaSet controller ensures `.spec.replicas` matches number of Pod objects — if fewer, it creates Pod objects.

**Implementation & mapping to OS-level:**

* Controllers are processes (system processes or pods) — e.g., controllers in `kube-controller-manager` or a custom operator. So the “controller” is a process that uses network sockets to talk to the API server (HTTP/2) and files for config.
* When controllers act (e.g., create a Pod), the action is an API write to etcd (eventually writing files on the control-plane host for etcd); the kubelet on target node will see the new object via watch and spawn Linux-level container processes.
* Controllers interact with external systems via network sockets (cloud APIs, storage controllers using gRPC/HTTP) — those are processes and TCP/HTTP connections at the OS level.

**Examples:**

* ReplicaSet controller: ensures pods count; creates Pod objects (API -> etcd).
* Deployment controller: creates/updates ReplicaSets, rolling updates.
* StatefulSet controller: creates Pods with stable identities and ensures ordered startup/teardown.
* PV/PVC controllers: bind PersistentVolumes and manage reclaim policies (often interacts with cloud APIs or CSI controllers).
* Custom controllers (operators): watch CRDs and reconcile complex resources.

---

# 4 — What is a CRD (CustomResourceDefinition)?

**Short:** CRD is a Kubernetes API extension mechanism — it lets you define new API object types (custom resources) that the API server stores in etcd like built-in resources.

**How CRD works (internals & flow):**

* You create a `CustomResourceDefinition` object. The kube-apiserver registers that new type, so you can `kubectl get myresources.mygroup.example.com`.
* CRDs are persisted in etcd just like other objects. There’s no built-in controller behavior for the custom resources by default — CRD just gives you storage & API for the custom type.
* To make CRDs useful you typically implement a controller/operator that watches those custom resource objects and reconciles them (same controller pattern). That controller is a process (pod) and makes changes to the cluster or external systems.

**OS-level mapping:**

* The CRD itself is metadata stored in etcd (files on disk belonging to etcd process).
* The operator that acts on CRs is a process/pod that opens API connections (sockets) to the API server. When that operator takes action (e.g., create cloud VMs, attach volumes), it opens more sockets to cloud APIs or creates files/devices on nodes.

**Common operator architecture:**

* CRD + Controller (operator) pair:

  * CRD = schema & API storage (etcd).
  * Controller = process watching CRs & implementing business logic (creates pods, PVs, external resources).

---

# 5 — Service Object (5.a, 5.b, 5.c)

## 5.a — What is the Service object?

**Short:** A `Service` is a stable network abstraction that defines a logical set of Pods and a policy to access them (cluster IP, DNS name, port). It decouples clients from ephemeral Pod IPs. Example: `Service` with `selector` pointing to labels picks matching Pods; ClusterIP gives a virtual IP inside cluster.

## 5.b — At the end, Service turns into what Linux objects?

A `Service` is a high-level concept; it is implemented by lower-level networking constructs — primarily:

* **IP tables / IPVS rules** (kernel objects manipulated via netfilter/nftables): DNAT and load-balancing rules that redirect traffic to backend pod IPs/ports.
* **Virtual IP (VIP)** concept: not necessarily a real network interface; in some implementations you can see an `iptables` rule for a cluster IP. In certain CNI setups, a `dummy` interface or `ip rule` may be used to bind IPs.
* **Sockets and listening processes**: the ultimate endpoint that receives traffic is a process in the pod (e.g., nginx), which has a listening socket.
* **Host port allocations** (for NodePort): that maps to ports on the host network stack — kernel listens on those TCP/UDP ports.
* **Cloud load balancer rules and forwarding rules** (for LoadBalancer Services): cloud network objects (external) and corresponding forwarding rules configured via cloud APIs.

So in OS terms: Services produce iptables/ipvs rules, host sockets (if NodePort/LB), and possibly cloud forwarding objects — all of which are realized via kernel networking objects and user-space control processes.

## 5.c — Which Kubernetes components do the conversion?

* **kube-apiserver** stores the Service object (API).
* **kube-controller-manager** (or specific controllers) may react for Service types where external resources are involved:

  * For `LoadBalancer` Services, the cloud-controller-manager will call the cloud API to provision an external LB and update the Service status with an external IP.
  * EndpointSlice controller / Endpoint controller produce EndpointSlice objects that record backend addresses.
* **kube-proxy** (on each node) is the component that takes Service + Endpoint/EndpointSlice objects and programs the node’s networking stack — typically by creating iptables or ipvs rules that translate traffic destined to the Service ClusterIP/NodePort to actual pod IP:port backends. So kube-proxy is the one that actually writes the kernel-level `iptables`/`ipvs` entries / manipulates `nftables`.
* **CNI plugin** does not implement Services directly, but it configures pod network connectivity so that kube-proxy rules can reach pod IPs.
* **CoreDNS** implements the DNS name for Service (DNS is a separate component — a deployment that responds DNS queries and is implemented by a process that listens on UDP/TCP port 53 — so ultimately sockets and files).

**Notes/variants:**

* In some implementations (e.g., kube-router), Service logic may be implemented by the CNI plugin itself.
* In ipvs mode, kube-proxy programs kernel IPVS service tables (`ip_vs` kernel module). Those are kernel load-balancer tables.

---

# 6 — Pod Object (6.a, 6.b, 6.c)

## 6.a — What is the Pod object?

**Short:** A Pod is the smallest deployable unit in Kubernetes: one or more containers that share the same network namespace and certain volumes. Pod is an API object (metadata + desired spec) stored in etcd; it’s not a Linux process itself.

## 6.b — At the end, Pod becomes which Linux objects?

A Pod’s spec leads to the creation of many OS-level objects:

1. **Linux processes**: container runtime spawns real processes (e.g., PID 1234) for each container using `runc` (or other OCI runtimes). These are real kernel processes.
2. **Namespaces**:

   * **Network namespace**: each pod typically gets its own netns (unless using hostNetwork). Internally that’s a kernel net namespace object linked to container processes (`/proc/<pid>/ns/net`).
   * **PID namespace** (optional): isolates process IDs inside the Pod.
   * **Mount namespace**: each container gets its own mount namespace; volumes are mount points.
   * **IPC, UTS, user namespaces** as configured.
3. **cgroups**: groups created for the pod/container for CPU/memory/io accounting (under `/sys/fs/cgroup/`).
4. **File system mounts**: Volume mounts (e.g., hostPath, emptyDir, CSI mounts) become real mountpoints inside the container's mount namespace. The kernel sees these as mounted filesystems or bind mounts.
5. **Network devices**:

   * `veth` pair connecting pod netns to host bridge or other CNI construct.
   * Bridge device, routes, iptables rules.
6. **Socket endpoints**: Process inside pod listens on TCP/UDP ports (kernel socket objects).
7. **Files on disk**: container image layers are stored under container runtime directories (e.g., overlayfs under `/var/lib/containerd/overlayfs`), log files under `/var/log/containers`, containerd metadata files, etc.
8. **Device nodes**: if container has devices (block devices), device nodes appear under `/dev` in container.

## 6.c — Which Kubernetes components do this conversion?

* **kubelet**: primary component on the node that observes pod objects assigned to the node and attempts to run them. It calls the CRI endpoint to create containers, sets up mounts, etc.
* **Container runtime (CRI implementation)** — commonly `containerd` with `runc`:

  * `containerd` downloads images, prepares filesystem layers (overlayfs), and uses `runc` to create a container (which results in kernel-level namespaces & processes).
* **CNI plugin**: invoked by kubelet (through `containerd`/CRI) to set up networking for pod: creates veth, assigns IP, sets up routes and iptables as necessary.
* **CSI drivers** & volume plugins: invoked by kubelet to attach/mount storage (block devices, mount points). CSI controllers (controller-side) may talk to storage systems to provision volumes.
* **kube-apiserver**: stores the Pod object; kubelet watches the API for pods.
* **kubelet + systemd**: kubelet may rely on systemd for some host-level operations; logs are managed by journald or runtime logs.

**Example sequence (simplified):**

1. Scheduler places Pod on Node (API update with `.spec.nodeName`).
2. Kubelet sees Pod (watch), calls CRI `CreateContainer` → container runtime creates container: overlayfs mounts for image, `runc` creates a process with pid, namespaces & cgroups.
3. Kubelet calls CNI to set up networking: creates veth & routes so pod IP is reachable.
4. CSI driver may attach block device and kubelet mounts it into container mount namespace.
5. Container process starts — now user app runs and listens on sockets.

---

# 7 — Ingress object (7.a, 7.b, 7.c)

## 7.a — What is the Ingress object?

**Short:** `Ingress` is a high-level API that describes external HTTP(S) routing rules for services inside the cluster (host/path → service:port). The `Ingress` resource is just configuration: it declares routes — it does not implement them by itself.

## 7.b — At the end, Ingress becomes what Linux objects?

Ingress itself is converted by an **Ingress Controller** into real networking artifacts, which are ultimately Linux objects like:

* **Reverse proxy process** (e.g., `nginx`, `haproxy`, `traefik`, `envoy`) running as pod(s) or host processes — these are real processes that open sockets and accept connections.
* **Configs and files**: Ingress controller writes config files (e.g., `nginx.conf`) to disk (inside the controller pod or host) — files are kernel objects on disk.
* **Sockets / listening ports**: processes listen on host ports or node ports (often 80/443) — kernel socket objects.
* **TLS key files**: Secrets holding certificates are mounted into the ingress controller pod as files, so TLS keys are files on filesystem.
* **iptables / ipvs / routes**: traffic might be directed via iptables or host network configuration, depending on how external access is set up.
* **Cloud Load Balancer resources**: In cloud setups, the ingress controller or cloud-controller-manager can configure external load balancers — these are external network objects.

## 7.c — Which Kubernetes components do this conversion?

* **Ingress resource** is stored by the **kube-apiserver**.
* **Ingress Controller** (a pod or set of pods you install — e.g., `nginx-ingress-controller`, `traefik`, `contour`, `gloo`, `istio` gateway) watches Ingress objects (List/Watch).

  * The controller translates Ingress rules into concrete reverse-proxy config and reloads the proxy process (writing config files and sending SIGHUP or using a control API).
  * The controller is a user-level process (container) that creates files, sockets and typically opens host ports (often via hostNetwork or NodePort+Service).
* **If you use a cloud-managed ingress (e.g., GKE Ingress), the controller talks to cloud APIs to provision external LBs** — cloud-controller-manager or the ingress provider will perform API calls which create cloud LB objects.
* **Service + kube-proxy + endpoints** are still used for routing traffic from ingress controller to backend pods.

**Summary:** Ingress resource → watched by Ingress Controller (a running process/pod) → controller writes proxy config & runs reverse proxy → kernel sockets, files, iptables/nat and possibly cloud LBs are created.

---

# 8 — What is the webhook concept?

**Short:** A webhook in Kubernetes is a way to call an external HTTP service during admission (or conversion) to inspect/modify/validate API requests. There are two common types: **admission webhooks** (mutating and validating) and **conversion webhooks** for CRDs.

**How it works (flow):**

* A client sends a request to `kube-apiserver` (e.g., `kubectl create pod ...`).
* `kube-apiserver` invokes configured admission webhooks (synchronously or asynchronously as configured) — it sends an `AdmissionReview` request to the webhook service (HTTP POST with JSON).
* The webhook service (could be a pod inside cluster or external) replies with allow/deny or modifications (mutating webhook).
* The API server applies the webhook’s decision/modifications before persisting the object to etcd.

**OS-level mapping:**

* **Webhook service** is a process (pod) that listens on TCP/HTTP ports — kernel socket objects.
* The API server performs an HTTP client call (outgoing socket) to reach the webhook. That call is a network connection from the apiserver process to the webhook address (in-cluster service IP or external URL).
* Webhook behavior may result in changes to files or firing other network calls depending on webhook logic.

**Practical notes:**

* Webhooks require TLS (kube-apiserver uses certificates to authenticate). The webhook server must have a serving cert; CA must be provided to the API server (or use service reference with CA bundle in webhook configuration).
* If the webhook is unavailable and `failurePolicy: Fail` is set, it can block API requests — this is a reliability/capacity consideration. So webhooks are real network dependencies — a failed webhook -> failed API calls.

---

# 9 — Different Types of Services and where to use each

Kubernetes `Service` types and when to use them — with their OS-level effect:

1. **ClusterIP** (default)

   * **What it is:** Internal-only virtual IP reachable within cluster.
   * **Use-case:** internal microservice communication (backend services, internal APIs).
   * **Implementation:** kube-proxy programs iptables/ipvs rules mapping ClusterIP:port → backend Pod IPs. DNS (CoreDNS) creates `<service>.<namespace>.svc.cluster.local` mapping to ClusterIP.
   * **OS-level impact:** iptables/ipvs entries on each node; no external firewall or cloud resources.

2. **NodePort**

   * **What it is:** Exposes the Service on a static port on each node (30000–32767 by default).
   * **Use-case:** simple external exposure without cloud LB, or used by external LBs forwarding to node ports.
   * **Implementation:** kube-proxy adds rules to accept host port and DNAT to Pod backends. Kernel listens on host port.
   * **OS-level impact:** host TCP/UDP ports opened (kernel sockets), iptables rules; potential port conflicts. You may see processes listening (ingress controller or node process if hostNetwork). Note: NodePort typically does not create an actual process bound to the port; instead kube-proxy DNATs traffic destined to nodePort to backend Pods’ IP:port.

3. **LoadBalancer**

   * **What it is:** Requests a cloud provider external load balancer (LB) and assigns an external IP. Only supported in environments with a cloud provider integration or MetalLB (on bare-metal).
   * **Use-case:** production external exposure with cloud-managed LB (managed health checks, stable IP).
   * **Implementation:** cloud-controller-manager or cloud-specific controllers call cloud APIs to provision an LB and configure backend target pools pointing to node ports or instance groups; kube-proxy still handles cluster networking.
   * **OS-level impact:** external cloud LB (external network object), forwarding rules, health checks; on nodes you still have iptables rules; traffic arrives at nodes as forwarded by cloud LB.

4. **ExternalName**

   * **What it is:** Maps a Service name to an external DNS name (CNAME) without creating endpoints.
   * **Use-case:** reference external services (e.g., `database.prod.external`) via a service name in cluster.
   * **Implementation:** CoreDNS returns a CNAME answer for the service DNS record; no iptables or kube-proxy rules created.
   * **OS-level impact:** purely DNS mapping — files are not created; just DNS responses from CoreDNS process.

5. **Headless Service (ClusterIP: None)**

   * **What it is:** No ClusterIP, used when you need direct pod endpoints (e.g., stateful sets). Kubernetes creates endpoints or EndpointSlices for the pod IPs; DNS returns pods’ A records.
   * **Use-case:** stateful applications, direct client-side load balancing, service discovery (e.g., databases, Cassandra).
   * **Implementation:** No iptables VIP. Clients discover backend pod IPs via DNS (CoreDNS).
   * **OS-level impact:** EndpointSlice objects exist in etcd; kernel networking isn't programmed with VIPs for that service — clients talk directly to pod IPs.

**Additional considerations:**

* **EndpointSlice** replaces Endpoints in many clusters: controller produces EndpointSlice objects (more scalable). These are API objects stored in etcd.
* **kube-proxy modes**:

  * `iptables` mode: kube-proxy writes iptables rules (netfilter).
  * `ipvs` mode: kube-proxy programs kernel IPVS tables (requires `ip_vs` kernel module).
  * `userspace` mode: deprecated/rare — proxy runs in userspace.

**Which component converts Service to kernel/network objects:**

* **kube-proxy** is the primary agent that turns Service + Endpoints/EndpointSlice into node-level iptables/ipvs rules.
* **cloud-controller-manager** / cloud provider plugins create external LB resources when Service type is LoadBalancer.
* **CoreDNS** supplies Service DNS records (maps `service.namespace.svc.cluster.local` to ClusterIP).

---

# Putting it all together — mindset your senior likes

Your senior said: *“none of these K8s objects are real at the low level; the real things are processes and files.”* That’s exactly correct. Use this mental mapping when troubleshooting or learning:

* **Kubernetes objects** (Pod, Service, Ingress, PVC, CRD, etc.) = declarations stored in **etcd** (files on disk belonging to the etcd process). They’re visible via the API server.
* **Controllers / components** (kube-scheduler, controller-manager, operators) = processes that watch the API and perform actions. They open sockets and write files (logs, state).
* **Actions performed by controllers** cause **kernel-level artifacts**:

  * Containers = kernel processes with namespaces & cgroups.
  * Volumes = block devices, file mounts, mountpoints.
  * Services = iptables/ipvs rules, host ports, cloud forwarding rules.
  * Ingress = reverse-proxy processes (nginx/traefik/envoy) and their config files + TLS file secrets.
  * Webhooks = HTTP services (pods) responding to apiserver; if they fail, API calls fail.

When your senior gives a hint like “check the host,” translate it to OS checks:

* Are the container processes running? `ps -ef` / `crictl ps`
* Is the network namespace present? `ip netns` / `ip link`
* Are iptables/ipvs rules present? `iptables -t nat -L -n -v` / `ipvsadm -Ln`
* Are files mounted? `findmnt` / `mount | grep <volume>`
* Is the apiserver reachable? `ss -ltnp | grep kube-apiserver` or `kubectl get --raw /healthz`
* Is the kubelet healthy? `journalctl -u kubelet -f`
* Are controller logs showing errors? `kubectl -n kube-system logs kube-controller-manager-<node>`

---

# Example quick troubleshooting recipes (practical)

* Pod stuck `ContainerCreating`:

  * Check kubelet logs (`journalctl -u kubelet`) — look for CSI attach/mount errors or image pull errors.
  * On node: `crictl ps -a` to see containers and statuses; check `/var/lib/kubelet/pods/<uid>/volumes` for mount issues.
* Service not routing:

  * Check `kubectl get svc` and `kubectl get endpoints` / `kubectl get endpointslices`.
  * On node: `iptables -t nat -L KUBE-SERVICES -n -v` or `ipvsadm -Ln`.
  * Check kube-proxy logs (`kubectl -n kube-system logs kube-proxy-<node>`).
* Ingress not reaching backend:

  * Check ingress controller pods logs and their generated config files (inside controller pod or mounted config path).
  * Confirm TLS secrets are mounted as files in the ingress controller pod.

