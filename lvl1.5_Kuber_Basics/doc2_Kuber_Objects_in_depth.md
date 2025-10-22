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

**Short:** A Node is a worker machine in Kubernetes (VM or physical) that runs pods.  <br>
**System-level view / final reality:** 
- a Node is a Linux host (processes & files) 
  - with kubelet (a process) 
  - container runtime (containerd, runc) 
  - CNI ([Container Network Interface](https://www.tigera.io/learn/guides/kubernetes-networking/kubernetes-cni/)) plugin processes 
  - systemd unit(s)  
  - and various directories under 
    - `/var/lib/kubelet` 
    - `/var/run` 
    - `/etc/kubernetes` 
The Node’s “Kubernetes identity” is mostly metadata in the API server backed by `etcd`, but at runtime the real work happens in host-level `processes`, `network namespaces`, `cgroups`, and `files`.

**Components & responsibilities (high level):**

* `kubelet` (process on the node): watches the `API server` for pods assigned to this node, creates containers via [CRI](<https://kubernetes.io/docs/concepts/architecture/cri/#:~:text=The%20Container%20Runtime%20Interface%20(CRI,components%20kubelet%20and%20container%20runtime.>), mounts volumes, manages pod lifecycle, reports status to API server.
* Container runtime (`containerd` + `runc`): implements containers as Linux processes using [namespaces](https://www.vmware.com/topics/kubernetes-namespace#:~:text=Namespaces%20are%20a%20way%20to,projects%20share%20a%20Kubernetes%20cluster.) [Namespace in linux wikipedia](https://en.wikipedia.org/wiki/Linux_namespaces#:~:text=Namespaces%20are%20a%20required%20aspect,type%2C%20used%20by%20all%20processes.) and [cgroups](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/resource_management_guide/chap-introduction_to_control_groups#:~:text=The%20control%20groups%2C%20abbreviated%20as,processes%20running%20on%20a%20system.).
* `CNI` (Container Network Interface) plugin (bridge, calico/flip/flannel): sets up pod networking (veth pairs, veth<>bridge, routes, iptables rules).
* `kube-proxy` (daemon on node or as pod): implements Services (iptables/ipvs rules or userspace proxy).
* `kubelet volume` plugin/CNI/[CIFS](https://ambidextrous-dev.medium.com/using-cifs-volumes-in-kubernetes-d450ea1cb0e4) drivers/CSI/other drivers: interact with kernel and disk.

**What gets created on Linux when a pod is scheduled to a node:**

* Processes (container processes) — `runc` (runC is a container runtime based on the Linux Foundation's Runtime Specification `runtime-spec`. runC is developed by the Open Container Initiative. [more](https://www.docker.com/blog/runc/)- spawns real processes inside namespaces. Each container is one or multiple processes seen by the kernel.
* Namespaces (PID, NET, MNT, IPC, UTS, user): Linux kernel namespaces isolate the container from the host (A network namespace is a logical copy of the network stack from the host system. Network namespaces are useful for setting up containers or virtual environments. Each namespace has its own IP addresses, network interfaces, routing tables, and so forth.).
* cgroups: the container runtime places the container's processes in cgroups for resource limiting and accounting cgroups (abbreviated from control groups) is a Linux kernel feature that limits, accounts for, and isolates the resource usage (CPU, memory, disk I/O, etc.) of a collection of processes.
* Files and mountpoints: volumes are mounted into container mount namespaces (bind mounts, FUSE, block device mounts).
* Network objects: veth pair, a peer in a bridge or a macvlan; routes; iptables / nftables rules; network namespace directory under `/proc/<pid>/ns/net`.
* Files under `/var/lib/kubelet/pods/<podUID>` with pod-related volume data, pod manifests, containers’ log files (often under `/var/log/pods` or `/var/log/containers`).

**Where to look / commands:**

* `kubectl get nodes` / `kubectl describe node <node>` (API layer)
* On node: `systemctl status kubelet` / `journalctl -u kubelet -f` (Journalctl is a utility for querying and displaying logs from journald, systemd's logging service. [more](https://www.loggly.com/ultimate-guide/using-journalctl/#:~:text=Journalctl%20is%20a%20utility%20for,from%20journald%2C%20systemd's%20logging%20service.))
* Running containers: `crictl ps` or `ctr -n k8s.io containers list` / `docker ps` (if docker)
* Pod files: `/var/lib/kubelet/pods/` and `/var/log/pods/` (or container runtime logs)
* Network: `ip netns`, `ip link`, `brctl show`, `iptables -t nat -L -n -v` or `ipvsadm -Ln` (if ipvs mode)

---

# 2 — Control plane components

## 2.a — What are the main components of the control plane?

* **kube-apiserver** — the API endpoint (An endpoint is any device that connects to a computer network. [more](https://www.cloudflare.com/learning/security/glossary/what-is-endpoint/)), the single source of truth entry point (reads/writes to `etcd`).
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

  * Runs control loops for many core controllers
    - Node controller
    - ReplicationController
    - Deployment controllers via ReplicaSet
    - Service Account & Token controllers
    - PersistentVolume controllers
    - Endpoint controllers
    - and others ...
  * Each controller watches 
    - resources in the API
    - computes `diff`s between desired & actual
    - executes actions by talking to API server
    - this leads to kubelet actions via watch events

* **kube-scheduler**

  * Runs scheduling algorithm: 
    - filters nodes
    - scores them
    - picks a node
    - updates Pod spec with `.spec.nodeName`.
  * Also runs as a process, communicates via the API.

* **cloud-controller-manager**

  * Talks to cloud provider APIs 
    - create load balancers
    - manage routes
    - attach volumes
  * Uses controllers like Service/Node/Route that perform cloud-specific work.

## 2.c — How to read logs of each component

There are two typical deployments: control-plane components 
  - as static pods (kubeadm style)
  - systemd-managed processes. 
How you read logs depends on that.

**If components run as static pods (common with kubeadm):**

* Control plane static pod manifests live at `/etc/kubernetes/manifests/` on control-plane nodes. The kubelet runs them as pods; container runtime runs them.
* Use `kubectl -n kube-system get pods` to list pods (e.g., `kube-apiserver-<node>`).
* Use `kubectl -n kube-system logs kube-apiserver-<node>` (or `kubectl logs -n kube-system <pod> -c <container>`) to view logs.
* On host, container runtime logs or journal: `docker logs` / `ctr` / `journalctl -u kubelet`.

**If components run as systemd units (older or custom setups):**

* `systemctl status kube-apiserver` and `journalctl -u kube-apiserver -f`.
  - `systemctl` is the central tool to manage systemd services, including starting, stopping, restarting, enabling, and disabling services. [more](https://www.digitalocean.com/community/tutorials/how-to-use-systemctl-to-manage-systemd-services-and-units)
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

* **Audit logs are produced by the kube-apiserver**. The apiserver writes audit events based on 
  - `--audit-policy-file`
  - `--audit-log-path`. 
So the kube-apiserver process (or pod) is the source of audit logs.
* **Where the logs actually reside depends on setup:**

  * If apiserver is a static pod: 
    - its container stdout/err can be read with `kubectl logs -n kube-system kube-apiserver-<node>`; 
    - if `--audit-log-path` points to a file path, the audit log may be written to a file inside the apiserver container filesystem, 
    - if this file has been mounted to the host (e.g., hostPath) then the file is accessible on the host under `/var/log/kubernetes/audit.log` or similar.
  * In many managed clusters
    - a logging agent (fluentd, filebeat)
    - a sidecar/daemonset 
  collects apiserver logs and ships them elsewhere.
* **Summary:** the apiserver (pod/process) produces audit records — where they end up (file on host, stdout, external system) depends on `--audit-log-path` and your logging configuration.

---

# 3 — What is the “controller” concept in Kubernetes?

**High-level:** A controller is a control loop — a process that watches the cluster state (via the API) and takes actions to move the current state toward the desired state declared in objects. “Controller” is the pattern; the implementation is a program/process.

**How it works (flow):**

1. Controller watches resources (`List` + `Watch`) from the apiserver (`etcd`).
2. When an object changes (or periodically), controller reconciles: 
  - reads desired state from the object’s `spec`
  - reads the actual state (from `API` or node `metrics`)
3. Controller issues changes by updating resources via the API (create/delete/update). For example:
  - ReplicaSet controller ensures `.spec.replicas` matches number of Pod objects — if fewer, it creates Pod objects.
  - More examples *ToDo*

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

10 — The Kubelet
10.a — What is the Kubelet?

Short definition:

Kubelet is the node-level agent in Kubernetes.
It runs on every node and is responsible for making the PodSpec on that node real — in other words, it watches the API for Pods assigned to its node, and ensures that the containers for those Pods are created, healthy, and match the declared spec.

It’s the bridge between the Kubernetes control plane (declarative state) and the real operating system (processes, network, files, mounts, etc.).

Kubelet in the Kubernetes hierarchy
Layer	Example Component	Description
Control plane (global desired state)	kube-apiserver, controller-manager, scheduler	Manage what “should” exist
Node-level agent (enforces local state)	kubelet	Ensures what “should exist” actually runs on this node
OS-level reality	containerd, cgroups, iptables, mounts, processes	The kernel-level execution of those Pods

So if you think of Kubernetes as a brain–body system:

The API server is the brain — it remembers what should exist.

The scheduler/controller-manager are the nervous system — they send “signals” about what to create.

The kubelet is the muscle — it takes those signals and performs the real physical actions on the node.

What kubelet actually does

Registers its node object with the API server (Node resource).

Watches for Pod objects with .spec.nodeName = this node.

For each pod:

Pulls container images via the container runtime (via CRI).

Sets up volumes and mounts (via CSI or in-tree plugins).

Calls the CNI plugin to create the pod network namespace and veth pair.

Starts containers via runc through the container runtime.

Reports pod and node status to the API server.

Periodically reports health and resource usage (CPU, memory, disk, conditions).

Runs liveness/startup probes against containers (HTTP, TCP, or exec).

Handles graceful termination and cleanup when pods are deleted.

Kubelet = process + gRPC API + watchers

It’s a systemd service or a static binary on every node (process name: kubelet).

Opens ports (default 10250, 10255) — HTTP(S) endpoints for metrics, logs, exec, etc.

Talks via gRPC and HTTP/2 to:

API server (for objects)

container runtime (CRI)

CNI plugin

CSI plugin

Stores its local state under:

/var/lib/kubelet/ — pod manifests, volume data, plugin sockets.

/var/lib/kubelet/pods/<uid> — per-pod directories (volumes, secrets, etc.).

/var/lib/kubelet/plugins/ — CSI driver sockets.

So kubelet is itself just one long-running Linux process that keeps the node converged with what’s in etcd via the API server.

10.b — At the end, kubelet is going to do what with other Kubernetes and Linux objects? Will it itself turn into Linux processes as well?

Yes — kubelet itself is a Linux process, and it creates and manages other Linux processes (containers) and kernel objects.

Let’s break that into two directions:

(1) How kubelet itself manifests at the OS level

Binary process: /usr/bin/kubelet or /usr/local/bin/kubelet

System service: often managed by systemd (systemctl status kubelet)

Process tree: you can see it in ps -ef | grep kubelet

Open files/sockets: visible via lsof -p $(pidof kubelet); it opens sockets like:

/var/lib/kubelet/device-plugins/kubelet.sock (for device plugins)

/var/lib/kubelet/plugins_registry/ (for CSI driver sockets)

/var/run/dockershim.sock (older CRI endpoints)

/var/lib/kubelet/pod-resources/kubelet.sock (for resource reporting)

Listens on ports:

10250: HTTPS endpoint for API (authenticated)

10255: Read-only metrics endpoint (deprecated)

So the kubelet is just a user-space process that:

Opens sockets

Reads/writes files

Executes binaries (runc, CNI, CSI)

Mounts volumes (via syscalls)

Forks other processes (via CRI calls to runtime)

(2) What kubelet does to other Linux objects

When a Pod is assigned to a node:

Action	Linux effect	Performed by
Image pull	Container image layers downloaded, stored under /var/lib/containerd/ or /var/lib/docker/ as overlayfs directories	containerd (via kubelet’s CRI call)
Pod creation	Directory created under /var/lib/kubelet/pods/<uid>	kubelet
Volume mount	Filesystems mounted (bind, NFS, block, tmpfs)	kubelet using CSI / OS syscalls
Network setup	veth pairs, bridges, iptables rules	kubelet calls CNI plugin binaries (real processes)
Container start	Real Linux process (runc -> clone() syscalls -> PID, namespaces, cgroups)	containerd / CRI runtime
Probe checks	kubelet spawns short-lived processes (e.g., exec probes inside container namespaces)	kubelet
Logs	Files written under /var/log/containers/ (symlinked from container runtime)	container runtime + kubelet

So kubelet doesn’t “turn into” anything else, but it causes a whole tree of other Linux processes and kernel-level objects to appear.

For example:

PID 1010  /usr/bin/kubelet
 ├─ PID 1203 /usr/bin/containerd-shim-runc-v2 -namespace k8s.io ...
 │    └─ PID 1205 /usr/bin/runc create --bundle ...
 │         └─ PID 1210 /usr/local/bin/python app.py   <-- actual app process
 └─ PID 1300 /opt/cni/bin/bridge add ...


So kubelet → containerd → runc → container processes.

10.c — Which Kubernetes components are responsible for this conversion?

The kubelet works at the bottom of the Kubernetes stack, but it receives its instructions from the control-plane components:

Task	Kubelet interacts with	What happens
Watch Pod assignments	kube-apiserver	Kubelet watches for Pod objects with .spec.nodeName=thisnode
Start containers	Container Runtime (CRI) — containerd, runc, CRI-O	Kubelet sends gRPC requests: RunPodSandbox(), CreateContainer(), StartContainer()
Configure networking	CNI plugin	Kubelet runs plugin binaries (bridge, calico, flannel) that create veth, set IP, routes, iptables
Mount storage	CSI driver	Kubelet calls CSI gRPC endpoints to attach and mount volumes
Update status	kube-apiserver	Kubelet PATCHes pod status objects (Ready, ContainerStatuses)
Health and metrics	metrics-server / kube-controller-manager	Kubelet provides node metrics to metrics-server over HTTPS
Authentication and RBAC	apiserver & controller-manager	Kubelet presents certificates and tokens issued by control plane

So kubelet is the executor for the control plane’s intentions.
The scheduler decides where a pod runs → the kubelet makes it actually run.

10.d — Which Kubernetes Objects are managed by Kubelet?

Kubelet manages and interacts with several Kubernetes object types, but only a subset directly.

Directly managed:
Object	What kubelet does
Pod	Main object it enforces: creates containers, monitors health, reports status
Node	Registers itself and updates its status (conditions, capacity, allocatable, etc.)
Secret	Fetches and mounts as files (base64-decoded) inside pod via volumes
ConfigMap	Fetches and mounts as files inside pod
Volume / PVC / PV	Mounts and unmounts volumes (via CSI plugins); handles attach/detach
ServiceAccount Token	Automatically mounts service account tokens into pods
Probe / Liveness / Readiness	Executes probes (HTTP/TCP/exec) against containers
Static Pods (defined via manifest files)	Reads from /etc/kubernetes/manifests/ and ensures those pods run locally, even without API server
Indirectly interacts with:
Object	How it interacts
DaemonSet / Deployment / StatefulSet	Indirect — kubelet doesn’t manage them directly, but those controllers create Pod objects which kubelet executes
CSI Driver / CNI Plugin	Kubelet calls their gRPC endpoints; they expose Unix sockets under /var/lib/kubelet/plugins/
Service	Indirect — kubelet runs kube-proxy (which handles Services)
NodeLease (in kube-node-lease namespace)	Kubelet updates it periodically as a heartbeat (used by control plane to detect node liveness)
Summary table — kubelet reality check
Concept	Description	Linux-level manifestation
Kubelet itself	Node agent process	/usr/bin/kubelet, systemd service, PID, sockets
Watches Pod objects	From API server via HTTPS	TCP socket connections, HTTP requests
Creates containers	Via CRI runtime	Processes, cgroups, namespaces
Sets up networking	Via CNI	veth pairs, bridges, iptables
Mounts storage	Via CSI	mountpoints, device nodes
Reports status	Writes Pod/Node status to API	HTTP requests to API server
Static Pods	Watches manifest files	Files under /etc/kubernetes/manifests/
Health probes	Runs commands / network checks	Temporary subprocesses, sockets
Bonus: What happens when kubelet dies or is stopped?

The kubelet process stops — no more heartbeats → Node marked NotReady.

The containers (processes) keep running (they’re managed by the container runtime, not directly by kubelet).

After node-monitor-grace-period, controllers mark pods as Unknown → eventually reschedule new pods elsewhere if needed.

When kubelet restarts, it re-syncs state with runtime and reconciles.

✅ In one sentence (your “deep” definition):

Kubelet is a Linux process that acts as the node’s executor for Kubernetes; it watches the API server for Pod objects assigned to its node, and by calling container runtime, CNI, and CSI plugins through gRPC and binaries, it transforms high-level Kubernetes specifications (Pods, Volumes, ConfigMaps, Secrets) into real OS-level objects — processes, cgroups, mounts, and network interfaces — and reports their status back to the control plane through the API server.

We’ve looked at the kubelet, which is the “executor” for Pods.
Now we’ll go deep on kube-proxy, which is the “network enforcer” for Services — it’s the component that turns the idea of a Service object into real network behavior in Linux.

Let’s dive in with the same deep structure and OS-level mapping.

11 — kube-proxy
11.a — What is kube-proxy?

Short definition:

kube-proxy is the node-level network agent that implements Kubernetes Service objects in the Linux kernel by programming iptables, ipvs, or nftables rules.
It translates the abstract concept of “a stable virtual IP for a group of pods” into real packet routing and NAT on every node.

Analogy

If kubelet makes Pods exist, kube-proxy makes Pod communication possible.
Think of it like:

kubelet = spawns the containers (processes)
kube-proxy = wires up the network between them (kernel-level routing)

11.b — What kube-proxy does conceptually

In Kubernetes, a Service is a logical abstraction that gives you:

a stable ClusterIP (virtual IP)

a port

and a list of endpoint pods (the actual destinations)

But Linux doesn’t know what a “Service” is — the kernel only knows about:

IP addresses

routing tables

NAT

conntrack

sockets

interfaces

So kube-proxy’s job is:

Watch the Service and Endpoints/EndpointSlices objects in the API server.

For every new or updated Service, create or modify corresponding iptables/ipvs/nftables rules.

Those rules catch packets destined for the Service’s ClusterIP and redirect them to one of the real Pod IPs behind it.

Flow summary
API Server (Service + EndpointSlice)
           ↓
       kube-proxy
           ↓
iptables/ipvs rules on each node
           ↓
Linux kernel (conntrack, NAT)
           ↓
Packets forwarded to pod’s real IP


So kube-proxy doesn’t actually forward traffic itself —
it just configures the kernel to do so.

11.c — kube-proxy’s place in the architecture
Layer	Component	Responsibility
Control Plane	kube-apiserver	Stores and exposes Service and EndpointSlice objects
Node Agent	kube-proxy	Watches those objects and configures local kernel routing/NAT
Kernel / OS	Linux networking stack	Actually forwards packets according to the rules
Where kube-proxy runs

Runs as a DaemonSet (a Pod on every node)

Binary: /usr/local/bin/kube-proxy

Communicates with:

kube-apiserver (for Service and Endpoint updates)

Linux kernel (via netlink syscalls and iptables/ipvs commands)

Stores config in /var/lib/kube-proxy/config.conf or ConfigMap

So like kubelet, kube-proxy is a real Linux process running on each node.

11.d — What kube-proxy does at the OS level

Let’s see what happens step by step.

Step 1 — Watches the API server

Kube-proxy watches:

Service objects → tells it which virtual IPs to create.

EndpointSlice objects → tells it which real Pod IPs belong to each Service.

Step 2 — Programs kernel rules

Depending on the mode, kube-proxy uses one of these backends:

Mode	Mechanism	Tools / syscalls used
iptables (legacy)	Creates chains and NAT rules for each Service and Endpoint	iptables-restore, /proc/net/ip_tables_names
ipvs (modern)	Creates virtual services with real backend servers	/proc/net/ip_vs, ipvsadm via netlink
userspace (deprecated)	Proxy process listens on Service IP and forwards manually	TCP/UDP sockets in user space
Step 3 — Kernel handles the traffic

When a packet arrives:

Example: ClusterIP Service
Client pod → ClusterIP (10.96.0.5:80)
→ kernel hits iptables NAT rule
→ destination rewritten to PodIP (10.244.1.23:8080)
→ conntrack table remembers mapping
→ packet delivered to pod via CNI interface


So the kernel-level NAT tables do the actual load-balancing and forwarding — not kube-proxy itself.

Example: NodePort Service
External client → NodeIP:30000
→ kernel iptables prerouting rule → translate to PodIP:8080
→ conntrack manages session

Example: ExternalName Service

kube-proxy doesn’t create iptables rules — DNS resolves it to an external hostname.

Step 4 — Clean up

When a Service or Endpoint is deleted, kube-proxy removes the associated kernel rules.

11.e — Linux-level view of kube-proxy

You can see kube-proxy’s work with Linux tools.

Tool	What it shows
`ps aux	grep kube-proxy`
sudo iptables -t nat -L -n -v	Lists NAT rules that kube-proxy installed
cat /proc/net/ip_vs	Lists ipvs services if running in IPVS mode
ss -ltnp or netstat	Shows listening sockets (only in userspace mode)
conntrack -L	Shows active NAT connections handled by kernel
iptables mode example
# Example chain created by kube-proxy:
Chain KUBE-SERVICES (2 references)
target         prot opt source      destination
KUBE-SVC-XYZ   tcp  --  0.0.0.0/0   10.96.0.5  /* my-service:80 clusterIP */ tcp dpt:80

Chain KUBE-SVC-XYZ
target          prot opt source      destination
KUBE-SEP-ABCDEF tcp  --  0.0.0.0/0   10.244.1.23 /* pod endpoint */ tcp dpt:8080


So, a packet to 10.96.0.5:80 gets DNAT’d to 10.244.1.23:8080.

ipvs mode example
# cat /proc/net/ip_vs
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port Forward Weight ActiveConn InActConn
TCP  10.96.0.5:80 rr
  -> 10.244.1.23:8080 Masq 1 0 0
  -> 10.244.2.15:8080 Masq 1 0 0


That’s kube-proxy telling the kernel to load-balance between those pod IPs using the IPVS subsystem (like an L4 load balancer inside the kernel).

11.f — Which Kubernetes components does kube-proxy interact with?
Component	Purpose
kube-apiserver	Watch Service and EndpointSlice objects
kubelet	(Indirectly) because kubelet creates pods that become endpoints
CoreDNS	Works together for ClusterIP name resolution (DNS + routing)
Linux kernel	Installs iptables/ipvs rules via syscalls
conntrack	Tracks ongoing network connections
11.g — Which Kubernetes Objects does kube-proxy manage or depend on?
Object	Role
Service	Primary — defines ClusterIP, ports, selector
EndpointSlice	Holds the real Pod IPs for each Service
Node	kube-proxy runs on each Node
Pod	Not directly managed, but endpoints refer to pods
ConfigMap (kube-proxy config)	Holds mode and parameters (/etc/kubernetes/kube-proxy-config.yaml)
11.h — OS-level summary (what’s real vs abstract)
Kubernetes abstraction	kube-proxy’s action	Real Linux artifact
Service (ClusterIP)	Creates iptables/ipvs rules	NAT and routing entries in kernel
EndpointSlice	Maps service → pod IPs	DNAT entries or ipvs backend list
NodePort	Adds host port rule	iptables PREROUTING rule on eth0
ExternalName	No rule, handled by DNS	DNS A/alias record
kube-proxy Pod	Runs on node	Linux process (/usr/local/bin/kube-proxy)
kube-proxy configuration	Watched by process	Files under /var/lib/kube-proxy/

So, again, the only “real” things are:

Processes (kube-proxy, iptables, kernel threads)

Files (/proc/net/ip_tables_names, /var/lib/kube-proxy)

Network interfaces (veth, bridges)

Kernel tables (NAT, ipvs, conntrack)

Everything else (Service, Endpoint) is just YAML → API object → translated into kernel reality.

11.i — What happens if kube-proxy dies?

Existing iptables/ipvs rules remain — kernel keeps forwarding packets.

But new Services or Endpoints won’t update (rules become stale).

Once kube-proxy restarts, it re-syncs and reconciles the tables.

✅ In one deep sentence:

kube-proxy is a Linux process that watches Service and EndpointSlice objects from the API server and translates them into kernel-level NAT and routing rules using iptables, ipvs, or nftables; it never forwards traffic itself, but by configuring the kernel’s network stack, it turns abstract Kubernetes Services into real packet paths between processes — the ultimate bridge from YAML to IP packets.

You’ve now seen how kubelet (executes pods) and kube-proxy (routes traffic) act on each node.

Now let’s move up to the control plane and look at one of the most intelligent components — the kube-scheduler — the brain that decides where pods should run before kubelet executes them.

We’ll go through this in the same deep “concept → mechanism → OS reality” style.

12 — kube-scheduler
12.a — What is the kube-scheduler?

Short definition:

kube-scheduler is a control-plane component that watches for Pods without a .spec.nodeName and decides on which node they should run.
It’s responsible for the placement logic — matching pods to nodes according to constraints, resource availability, and scheduling policies.

It doesn’t run any pods itself; it just writes the decision (.spec.nodeName) into the Pod object in etcd through the API server.

After that, the kubelet on that chosen node takes over and makes it real.

Analogy:

If you think of Kubernetes as a restaurant:

The API server is the waiter (takes the order — Pod spec)

The scheduler is the manager (decides which chef should cook it — Node)

The kubelet is the chef (actually cooks it — spawns containers)

The container runtime is the stove (executes the process)

12.b — kube-scheduler’s role in the control plane
Layer	Component	Role
Declarative API	kube-apiserver	Receives YAML, stores objects
Decision logic	kube-scheduler	Decides which node should run the pod
Execution	kubelet	Creates containers, mounts, networking
Observation	controller-manager	Ensures replicas, scaling, etc.
12.c — What kube-scheduler actually does

Let’s go step by step, following a real pod’s lifecycle.

Step 1 — Pod creation

A user (or controller like a Deployment) creates a Pod object.
At this point, .spec.nodeName is empty, meaning it’s unscheduled.

Step 2 — Scheduler watches API

kube-scheduler continuously watches the API server for any Pods where:

.spec.nodeName == null

Step 3 — Filtering (a.k.a. Predicates)

The scheduler filters all nodes to find where this pod can run.
It evaluates:

Node taints and tolerations

Node selectors and affinity/anti-affinity

Resource requests (CPU, memory)

Volume attach limits

Node conditions (Ready, DiskPressure, NetworkUnavailable)

Custom scheduling plugins (via scheduler framework)

After filtering, it gets a subset of eligible nodes.

Step 4 — Scoring

For each eligible node, the scheduler assigns a score based on:

Free CPU/memory

Pod affinity rules

Spread constraints

Node labels or topology

Image locality (if already cached)

Scores are normalized, and the node with the highest total wins.

Step 5 — Binding

The scheduler doesn’t directly tell kubelet — instead, it makes a small API call:

POST /api/v1/namespaces/<ns>/pods/<podname>/binding


with:

target:
  kind: Node
  name: node-xyz


This updates .spec.nodeName = "node-xyz" in etcd (through the API server).

Step 6 — Handoff

Now that the Pod is bound, the kubelet on node-xyz sees it (because it watches for pods assigned to it) and proceeds to actually create the containers.

So, scheduler’s job is complete at that moment — it’s purely a decision-maker.

12.d — What kube-scheduler is at the OS level

Let’s map it down to Linux.

Level	Entity	Reality
Kubernetes concept	kube-scheduler	Binary process (/usr/local/bin/kube-scheduler)
Deployment type	Control-plane Pod (in kube-system namespace)	A real Pod running on a control-plane node
Process	Yes	You can see it with `ps aux
Communication	HTTPS to API server	TCP connection (port 6443 by default)
Storage	None (stateless)	Keeps ephemeral state in memory; config in /etc/kubernetes/scheduler.conf
Configuration	--kubeconfig, --leader-elect, --policy-config-file	Command-line flags passed to binary

So it’s a single Linux process (or set of replicas for HA) that continuously performs:

API calls (via TCP sockets)

JSON/YAML deserialization (Pod specs)

In-memory scheduling logic

Writes the chosen node back (HTTP POST)

It has no direct kernel-level side effects — no mounts, iptables, or processes — because it doesn’t run workloads.
Its output is purely metadata updates in the cluster database (etcd).

12.e — kube-scheduler’s input and output
Input	Source	Description
Pod (unscheduled)	kube-apiserver	The request to place something
Node list	kube-apiserver	The possible destinations
Node metrics	kubelet via API	Used for scoring
Affinity / Taints	Pod spec + Node labels	Used for filtering
Output	Destination	Description
Binding API call	kube-apiserver	Sets .spec.nodeName
Events	kube-apiserver	Records scheduling decisions and failures
12.f — Who runs and manages kube-scheduler

Typically:

It’s run as a static pod by the kubelet on the control-plane node.

The manifest file is usually at:

/etc/kubernetes/manifests/kube-scheduler.yaml


(so kubelet restarts it automatically if it dies)

The image is k8s.gcr.io/kube-scheduler:<version> or registry.k8s.io/kube-scheduler.

So kubelet on the master node manages kube-scheduler as a Pod — which means the scheduler itself is subject to the same lifecycle management as any other workload.

12.g — kube-scheduler and other components
Component	Interaction
kube-apiserver	Scheduler watches Pods and Nodes via the API, writes back bindings
etcd	Indirect — scheduler never talks to etcd directly, only through the API server
kube-controller-manager	Works alongside scheduler (controllers create Pods; scheduler places them)
kubelet	Indirect — executes Pods once bound to its node
metrics-server	Provides optional metrics for scoring decisions (CPU/mem utilization)
12.h — kube-scheduler and OS-level reality

If you strip away all the Kubernetes abstractions, here’s what’s real in Linux when kube-scheduler runs:

Real artifact	Example / Path	Purpose
Process	/usr/local/bin/kube-scheduler	Main binary
Sockets	TCP connection to API server (port 6443)	Watches Pods/Nodes
Files	/etc/kubernetes/scheduler.conf	kubeconfig
Logs	/var/log/kube-scheduler.log (or stdout in pod)	Activity logs
Memory structures	In-process cache of nodes/pods	Scheduling algorithms
System calls	connect(), read(), write()	HTTP communication

So it’s purely user-space computation — no syscalls like mount, clone, or iptables.
Its main “real-world” activity is network I/O and CPU cycles for running the scheduling algorithms.

12.i — kube-scheduler and the bigger system

Think of the Kubernetes ecosystem as a state machine that constantly moves the system from desired → actual:

Stage	Component	From	To	Real-world effect
Declarative spec	User → API server	YAML → etcd	Data in database	
Decision	Scheduler	Pod (unbound) → Pod (bound to node)	Metadata update	
Execution	Kubelet + CRI	Pod (bound) → running containers	Real Linux processes	
Networking	Kube-proxy	Service → iptables rules	Kernel packet routing	

So kube-scheduler’s position is: the moment before reality begins — it’s the last pure decision-making step before kubelet creates actual processes.

12.j — Example flow with real effects

Let’s trace a real example:

You apply:

apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
    - name: nginx
      image: nginx


The API server stores the Pod in etcd — no node assigned.

kube-scheduler sees it and evaluates:

Nodes A, B, C

Node B has least load → pick Node B

kube-scheduler sends:

spec:
  nodeName: node-b


(binding request)

kubelet on Node B detects it via watch, creates containers.

Now Linux reality appears:

containerd starts nginx process

veth pairs, cgroups, mounts created

network rules set up by CNI

So kube-scheduler never touches the kernel — it just triggers others to do it.

12.k — Logs and troubleshooting

You can check scheduler logs in:

kubectl logs -n kube-system kube-scheduler-<hostname>


Look for lines like:

I1019 09:23:45.512] Successfully bound pod "nginx" to "node-b"
I1019 09:23:45.512] Evaluated 3 nodes, 2 filtered, 1 feasible

12.l — Bonus: Scheduler plugins and extensions

Modern kube-scheduler is extensible via the Scheduling Framework, where you can add:

Filter plugins (custom node eligibility)

Score plugins (custom scoring logic)

Bind plugins (custom binding logic)

Reserve / PreBind / PostBind hooks

These run inside the same process, exposing extension points for advanced scheduling (e.g., topology-aware scheduling, GPU, affinity rules).

✅ In one deep sentence:

kube-scheduler is a control-plane process that continuously watches for unscheduled Pods in the API server, evaluates all cluster Nodes against resource, policy, and affinity constraints, computes the most suitable node through filtering and scoring algorithms, and binds the Pod by writing .spec.nodeName — thus transforming a high-level “desired workload” into a precise execution target; it never touches containers or kernel resources itself but acts as the logical bridge between the declarative API and the node-level executors (kubelets).

Now the most powerful brains of Kubernetes — the one that keeps everything alive, self-healing, and automated.

If the scheduler decides where things go, then the controller-manager decides what things should exist and keeps them existing.

Let’s go deep in the same structured “concept → logic → Linux reality” way again 👇

13 — kube-controller-manager
13.a — What is the kube-controller-manager?

Short definition:

The kube-controller-manager is a control-plane component that runs a collection of controllers — each one is a small control loop responsible for maintaining a specific part of cluster state.

It continuously watches the desired state (from etcd via the API server) and compares it with the current state (from the cluster).
If something drifts out of sync, it acts to fix it automatically — by creating, updating, or deleting Kubernetes objects.

Analogy:

Think of Kubernetes as an autopilot system:

The API server is the control panel (where you set what you want).

The scheduler is the planner (decides which runway to use).

The kube-controller-manager is the autopilot computer — constantly correcting the course to match your desired flight path.

So when you say:

“I want 3 replicas of Nginx,”
the controller-manager makes sure there are always exactly 3, even if one crashes.

13.b — What actually is a controller?

Each controller is just a loop that does this over and over:

Observe → Read current state from the API (through watches)

Compare → Check if current state == desired state

Act → If not equal, make API calls to change it

Example (simplified pseudo-code):

while True:
    desired = get("ReplicaSet.spec.replicas")
    current = count("Pods with owner=ReplicaSet")
    if current < desired:
        create_pod()
    elif current > desired:
        delete_pod()
    sleep(5)


This pattern is everywhere in Kubernetes — it’s called the controller pattern.

13.c — What controllers exist inside kube-controller-manager?

The kube-controller-manager process actually contains many controllers running as goroutines inside one binary.
Some of the most important ones are:

Controller	What it manages	What it ensures
Node Controller	Node objects	Marks Nodes as “NotReady” if unreachable
Replication Controller	ReplicaSets / Pods	Maintains correct Pod count
Deployment Controller	Deployments	Manages rolling updates & ReplicaSets
Endpoints Controller	Services & Pods	Keeps Service endpoints in sync
Service Account Controller	ServiceAccounts	Manages default service accounts
Namespace Controller	Namespaces	Cleans up objects when a namespace is deleted
PersistentVolume Controller	PVs and PVCs	Binds claims to volumes
Job / CronJob Controller	Jobs / CronJobs	Ensures jobs run to completion
DaemonSet Controller	DaemonSets	Runs pods on every node
ReplicaSet Controller	ReplicaSets	Ensures replicas exist
HorizontalPodAutoscaler	HPA	Adjusts replicas based on metrics

…and many more (over 40 small controllers in total).

Each one has its own control loop logic — all running inside a single process for simplicity.

13.d — kube-controller-manager’s role in the control plane

Here’s where it sits logically:

Layer	Component	Function
API + DB	kube-apiserver + etcd	Cluster’s source of truth
Decision logic	kube-scheduler	Chooses where Pods go
Reconciliation logic	kube-controller-manager	Ensures what exists stays as declared
Execution	kubelet	Actually runs the containers

So the controller-manager doesn’t start or schedule pods directly — it simply ensures the declarations in etcd are realized by other components.

13.e — Example: Deployment Controller in action

Let’s trace a real scenario 👇

You apply:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: nginx
          image: nginx


The API server stores the Deployment in etcd.

The Deployment Controller (inside kube-controller-manager) notices a new Deployment →
It creates a ReplicaSet object with replicas: 3.

The ReplicaSet Controller (also inside kube-controller-manager) notices the new ReplicaSet →
It creates 3 Pods.

The Scheduler binds those Pods to nodes.

The Kubelet runs them as containers.

So, the controller-manager created all the “intermediate” objects automatically — you didn’t manually create ReplicaSets or Pods.
That’s reconciliation in action.

13.f — Who runs and manages kube-controller-manager?

Just like the scheduler, the controller-manager usually runs as a static pod on the control-plane node.

File location:

/etc/kubernetes/manifests/kube-controller-manager.yaml


That manifest is watched by the kubelet on the control-plane node, so if the process crashes, kubelet restarts it.

The binary itself:

/usr/local/bin/kube-controller-manager


It’s launched with flags like:

--kubeconfig=/etc/kubernetes/controller-manager.conf
--leader-elect=true
--controllers=*,bootstrapsigner,tokencleaner

13.g — At the OS level
Level	Entity	Linux reality
Kubernetes concept	kube-controller-manager	A control-plane Pod
Execution	Static pod managed by kubelet	Real process on master node
Process	/usr/local/bin/kube-controller-manager	Seen via ps aux
Network	HTTPS to API server	TCP socket connection
Data	Watches, caches	In-memory state
Storage	None persistent	All state is in etcd

So just like the scheduler, it’s purely user-space logic — no direct kernel-level effects.
It’s a brain that uses API calls as its hands.

13.h — Which Kubernetes objects does kube-controller-manager manage?

Here’s a big-picture table 👇

Object	Responsible Controller	Goal
Pod	ReplicaSet / DaemonSet / Job controllers	Ensure the right number and placement
Node	Node Controller	Update node status, evict pods if dead
Service	Endpoints Controller	Keep endpoints up-to-date
Namespace	Namespace Controller	Delete dependents
PersistentVolumeClaim	PV Controller	Bind to a matching PV
ServiceAccount / Token	ServiceAccount Controller	Generate tokens
Deployment	Deployment Controller	Manage ReplicaSets & rollout
Job / CronJob	Job Controller	Create Pods for batch jobs
HPA / VPA	Autoscaler controllers	Scale workloads

In short:
→ Every high-level Kubernetes object has a corresponding controller loop somewhere — and most of them live inside the kube-controller-manager.

13.i — How controllers communicate

All controllers inside kube-controller-manager talk only through the API server — never directly with kubelet or etcd.

For example:

They watch objects (Pods, Nodes, PVs) via the API.

They POST/PUT updates (like new Pods, ReplicaSets, etc.)

API server handles persistence in etcd.

That makes them loosely coupled — you can restart one controller without breaking the others.

13.j — Self-healing behavior

This is the essence of Kubernetes.

If a Pod crashes:

The kubelet removes it.

The ReplicaSet Controller notices fewer Pods than desired.

It creates a new Pod (API call).

The Scheduler binds it.

The Kubelet starts it.

→ No human intervention needed.

That’s the controller-manager constantly bringing the system back into equilibrium — what we call reconciliation.

13.k — Logs and troubleshooting

To see what controllers are doing:

kubectl logs -n kube-system kube-controller-manager-<hostname>


You’ll see entries like:

I1019 10:15:33] Created pod: nginx-deploy-7f9dfd
I1019 10:15:34] Deleted pod: nginx-deploy-7f9dfd-old
I1019 10:15:40] Node node-2 notReady for 40s, marking unschedulable


You can also check the list of running controllers via:

kubectl get pods -n kube-system | grep controller

13.l — Relation to other components
Component	Relation
kube-apiserver	Main interface — watches & updates objects
etcd	Indirect storage (through API server)
kube-scheduler	Works after controllers create Pods
kubelet	Executes Pods once scheduled
cloud-controller-manager	Manages cloud resources (LoadBalancers, etc.) — separate process in cloud clusters
13.m — OS and network view

If you inspect a real control-plane node:

ps aux | grep kube-controller-manager


you’ll see something like:

root  2736  2.4  0.9  184532  61234 ?  Ssl  Oct19  1:02  /usr/local/bin/kube-controller-manager --kubeconfig=/etc/kubernetes/controller-manager.conf


And network sockets:

netstat -ntp | grep 2736


showing it talking to the API server at 127.0.0.1:6443.

So the only real activity is network I/O and JSON processing — it’s like a daemon running hundreds of small reconciliation loops in user space.

✅ In one deep sentence:

kube-controller-manager is a control-plane process that hosts a suite of independent control loops (“controllers”), each continuously reconciling the actual state of Kubernetes objects toward their desired state by observing cluster data through the API server and performing corrective actions (like creating Pods, updating endpoints, or cleaning namespaces); it never directly touches containers or nodes but orchestrates all other components by declarative intent, ensuring the cluster remains self-healing and consistent over time.

Now the beating heart of Kubernetes — the kube-apiserver ❤️‍🔥

If kubelet runs the containers, scheduler decides where to place them, and controller-manager keeps them alive —
then the API server is what connects all of them together.
It’s the only doorway to the cluster’s state and the only brain that talks to etcd directly.

We’ll unpack it with the same depth as before — from abstract concepts all the way down to Linux files, sockets, and syscalls.

14 — kube-apiserver
14.a — What is the kube-apiserver?

Short definition:

The kube-apiserver is the central API gateway and state manager of Kubernetes.
It exposes a RESTful HTTP API (/api, /apis) that all other components — kubectl, kubelet, scheduler, controller-manager, and even other Pods — use to interact with the cluster.
It validates, authenticates, authorizes, and persists every object in Kubernetes via etcd.

Analogy

Think of Kubernetes as a living organism:

kube-apiserver = the central nervous system (everything communicates through it)

etcd = the memory (stores the truth)

controllers and schedulers = reflexes and motor neurons (decide and act)

kubelet = the muscles (executes work on the body — the nodes)

No one talks directly to etcd except kube-apiserver.
If kube-apiserver is down → the entire control plane goes silent.

14.b — Responsibilities

Let’s break its key responsibilities in detail 👇

Responsibility	Description
1. REST API gateway	Serves the Kubernetes API (HTTP + JSON + gRPC). Every CLI command (kubectl get pods) and internal controller communication goes through it.
2. Authentication	Verifies the identity of the caller using tokens, client certs, or service accounts.
3. Authorization	Checks if the authenticated user can perform the requested action (RBAC, ABAC, Node, Webhook modes).
4. Admission control	Runs mutating/validating webhooks and admission plugins before persisting the object.
5. Validation	Ensures objects are structurally and semantically correct before storing them.
6. API aggregation	Serves custom APIs and CRDs under /apis via the API Aggregation Layer.
7. Persistence	Stores cluster state in etcd (all YAMLs, statuses, secrets, etc.).
8. Watch mechanism	Notifies clients (controllers, kubelets, etc.) of object changes in real-time using HTTP watches.
9. Versioning and conversion	Manages multiple API versions (v1, v1beta1, etc.) and converts between them.

Everything in Kubernetes — from kubectl apply to autoscaling — flows through these nine mechanisms.

14.c — kube-apiserver workflow (step-by-step)

Let’s take a single request as an example:

Example:
kubectl create -f pod.yaml

Step 1 — kubectl sends an HTTPS request

→ to the kube-apiserver endpoint (default: https://<control-plane>:6443)

POST /api/v1/namespaces/default/pods
Content-Type: application/json
Authorization: Bearer <token>
Body: { "apiVersion": "v1", "kind": "Pod", ... }

Step 2 — Authentication

kube-apiserver validates the caller:

Client certs → via kubeconfig

Bearer token → via service account or static token

Webhook auth → via external identity provider

Step 3 — Authorization

Checks if the user is allowed to perform this action (via RBAC).

If allowed → proceed.

Step 4 — Admission control

Passes through a chain of admission plugins, for example:

NamespaceLifecycle

LimitRanger

DefaultStorageClass

MutatingWebhook

ValidatingWebhook

Some mutate the object (e.g., inject sidecars), some validate it (e.g., enforce Pod security).

Step 5 — Object validation

Schema validation using OpenAPI and internal type structs.

Step 6 — Persistence

Converts the JSON into Go structs → serializes → stores it in etcd as a key-value pair.

/registry/pods/default/my-pod → serialized Pod object

Step 7 — Notification (Watch)

All interested controllers (scheduler, kubelet, etc.) that are watching /api/v1/pods get a notification that a new Pod appeared.

Step 8 — Response

Returns 201 Created to the client with the object in the response.

14.d — Real relationship between kube-apiserver and etcd

At the OS and process level:

kube-apiserver connects to etcd via gRPC over HTTPS

Configuration:
/etc/kubernetes/manifests/kube-apiserver.yaml
→ has --etcd-servers=https://127.0.0.1:2379

Each write is a transaction in etcd’s Raft-based store.

Every Kubernetes object corresponds to a key in etcd under /registry/<resource>.

Example (if you dump etcd):

/registry/pods/default/nginx-pod
/registry/deployments/default/frontend
/registry/services/default/backend


→ The API server is the only process that encodes/decodes and manipulates this data.
→ No other component should ever talk to etcd directly.

14.e — Which Linux objects are involved?

At the lowest level:

Component	Linux Reality
kube-apiserver	Real process (/usr/local/bin/kube-apiserver)
API endpoint	TCP socket listening on port 6443
Data store	Network connection to etcd (port 2379)
TLS certs	Files in /etc/kubernetes/pki/
Admission webhooks	HTTPS connections to webhook Pods or services
Logs	/var/log/kube-apiserver.log or Pod logs in kube-system

So the “real” things are:

Processes

Files

TLS sockets

HTTP requests

etcd key-value entries

All YAML objects you write (Pods, Services, CRDs) become serialized files in etcd, stored as bytes.

14.f — What happens when kube-apiserver runs

The kubelet on the control-plane node runs it as a static pod (like other control-plane components).

Manifest:

/etc/kubernetes/manifests/kube-apiserver.yaml


This pod runs the container:

image: k8s.gcr.io/kube-apiserver:v1.xx.x
command:
  - kube-apiserver
  - --etcd-servers=https://127.0.0.1:2379
  - --secure-port=6443
  - --service-account-key-file=/etc/kubernetes/pki/sa.pub
  - --client-ca-file=/etc/kubernetes/pki/ca.crt


At runtime, you can verify:

ps aux | grep kube-apiserver
netstat -tnlp | grep 6443

14.g — Which components talk to the kube-apiserver?

Everything.

Component	How it uses the API
kubectl	CLI client over HTTPS
kubelet	Registers nodes, reports Pod status, retrieves Pod specs
kube-scheduler	Watches unassigned Pods, writes binding decisions
kube-controller-manager	Watches objects, creates new ones
kube-proxy	Watches Services & Endpoints
CoreDNS	Reads ConfigMaps and Services
Webhooks & Operators	Register CRDs and admission hooks
Custom Controllers (CRDs)	Use same watch mechanism
Metrics-server / Prometheus	Query metrics endpoints

So it’s the single source of truth and single point of communication for the entire cluster.

14.h — Watch mechanism (OS perspective)

This is how controllers and kubelets “react instantly” to changes.

Under the hood:

Clients issue an HTTP GET request with ?watch=true

kube-apiserver holds the connection open (long-lived HTTP stream)

When an object changes, kube-apiserver pushes an event down that stream

This is implemented via Go channels + JSON streaming — not raw kernel-level sockets, but standard TCP HTTP responses.

At the system level:

A kube-controller-manager process maintains many long-lived TCP connections to kube-apiserver

kube-apiserver multiplexes them efficiently using Go’s goroutines and epoll under the hood

So, again — no magic — just processes, sockets, JSON, and file descriptors.

14.i — Authentication and Authorization mechanisms

Kube-apiserver can use multiple layers together:

Authentication plugins

Client certificate (--client-ca-file)

Bearer token

Bootstrap tokens

ServiceAccount JWT

Webhook or OIDC

Authorization plugins

Node (for kubelet)

ABAC (deprecated)

RBAC (mainstream)

Webhook

Admission

Runs webhook controllers or built-in mutators

Example: inject sidecars (Istio), enforce quotas, set defaults

These layers form the security pipeline of every request.

14.j — API Aggregation Layer and CRDs

Kube-apiserver can extend itself:

API Aggregation Layer → allows new API services (like metrics-server) to appear under /apis/metrics.k8s.io

CRDs (CustomResourceDefinitions) → let you define new object types (e.g., MyApp, DatabaseBackup)

In both cases, the kube-apiserver handles them just like built-in objects:

Validates

Stores in etcd

Exposes via REST

That’s how Kubernetes stays extensible.

14.k — Logging, monitoring, and audit
View logs:
kubectl logs -n kube-system kube-apiserver-<node>

Audit logs:

Kube-apiserver can generate audit logs for every request:

Configured via --audit-policy-file

Stored in /var/log/kubernetes/audit.log

Audit logs contain:

{
  "kind": "Event",
  "user": "system:kube-scheduler",
  "verb": "update",
  "objectRef": { "resource": "pods", "name": "nginx" },
  "stage": "ResponseComplete",
  "responseStatus": { "code": 200 }
}


So the audit log lives with the kube-apiserver pod —
it’s the one that sees every API call.

14.l — OS-level summary (what’s real)
Kubernetes abstraction	kube-apiserver’s concrete action	Real Linux artifact
kubectl apply	HTTP POST request	TCP socket + HTTPS
Pod YAML	JSON payload	Serialized key in etcd
RBAC rule	Validation logic	Data structure in memory
Webhook call	Admission request	HTTPS socket
Audit log	Log entry	File in /var/log/kubernetes/
CRD	New REST handler	Go struct and in-memory route

At the end of the day — the API server is a web server.
It just serves JSON that defines the universe of Kubernetes.

✅ In one deep sentence:

kube-apiserver is the central, stateful web server of Kubernetes that validates, authenticates, and stores all cluster objects in etcd; it’s the single gateway for every component and user, exposing the declarative model through REST endpoints, performing admission and authorization, and translating YAML manifests into real persisted objects and streaming updates over TCP — the ultimate bridge between human intent and the cluster’s operational state.

15 — etcd next?
That’s the persistent memory of Kubernetes — where all your Pods, Secrets, ConfigMaps, and state actually live as serialized files — and it ties directly to the “real Linux files and processes” your senior expects you to understand.

Webhook in Kubernetes is a mechanism that allows external systems to intercept and modify API requests. It's like a callback system that lets you inject custom logic into Kubernetes operations.

What Webhooks Manage:
Webhooks don't "manage" objects but rather intercept and validate/modify API requests for objects:

1. Validating Admission Webhooks
yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: pod-policy-validator
webhooks:
- name: pod-policy.validator.example.com
  clientConfig:
    service:
      name: policy-validator-service
      namespace: webhook-system
      path: /validate-pods
      port: 443
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1"]
  failurePolicy: Fail
  sideEffects: None
2. Mutating Admission Webhooks
yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: pod-injector
webhooks:
- name: pod-injector.mutator.example.com
  clientConfig:
    service:
      name: pod-injector-service
      namespace: webhook-system
      path: /mutate-pods
      port: 443
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1"]
  failurePolicy: Fail
  sideEffects: None
Objects That RECONCILE Webhooks (Webhook Servers):
Webhooks need external webhook servers to process the requests:

1. Custom Webhook Server Deployment
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: policy-webhook-server
  namespace: webhook-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: policy-webhook
  template:
    metadata:
      labels:
        app: policy-webhook
    spec:
      containers:
      - name: webhook-server
        image: my-org/policy-webhook:v1.0
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: certs
          mountPath: /etc/webhook/certs
          readOnly: true
      volumes:
      - name: certs
        secret:
          secretName: webhook-certs
---
apiVersion: v1
kind: Service
metadata:
  name: policy-webhook-service
  namespace: webhook-system
spec:
  selector:
    app: policy-webhook
  ports:
  - port: 443
    targetPort: 8443
2. Service Mesh Webhook (Istio)
yaml
# Istio automatically creates mutating webhooks for sidecar injection
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: istio-sidecar-injector
  labels:
    app: sidecar-injector
webhooks:
- name: sidecar-injector.istio.io
  clientConfig:
    service:
      name: istiod
      namespace: istio-system
      path: "/inject"
      port: 443
  rules:
  - operations: [ "CREATE" ]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
3. Cert-Manager Webhook
yaml
# Cert-manager uses webhooks for certificate validation
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: cert-manager-webhook
webhooks:
- name: webhook.cert-manager.io
  clientConfig:
    service:
      name: cert-manager-webhook
      namespace: cert-manager
      path: /validate
      port: 443
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["cert-manager.io"]
    apiVersions: ["v1"]
    resources: ["certificates", "issuers"]
When to Use Webhooks:
Use Case 1: Security Policies & Validation
yaml
# ValidatingWebhookConfiguration for security policies
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: security-policy-validator
webhooks:
- name: security.validator.example.com
  clientConfig:
    url: https://security-webhook.example.com/validate
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  # This webhook could reject pods that:
  # - Run as root user
  # - Use privileged containers
  # - Mount host paths
  # - Don't have resource limits
Use Case 2: Automatic Sidecar Injection
yaml
# MutatingWebhookConfiguration for automatic logging sidecar
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: log-sidecar-injector
webhooks:
- name: log-injector.mutator.example.com
  clientConfig:
    service:
      name: log-injector-service
      namespace: default
      path: /inject-log-sidecar
      port: 443
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  # This webhook automatically adds:
  # - Fluentd sidecar container
  # - Volume mounts for logs
  # - Environment variables
Use Case 3: Defaulting Values
yaml
# MutatingWebhookConfiguration for setting defaults
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: namespace-defaults
webhooks:
- name: namespace-defaults.mutator.example.com
  clientConfig:
    service:
      name: namespace-defaults-service
      namespace: webhook-system
      path: /default-namespace
      port: 443
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["namespaces"]
  # This webhook automatically adds:
  # - Default resource quotas
  # - Default network policies
  # - Default labels and annotations
Use Case 4: Custom Resource Validation
yaml
# ValidatingWebhookConfiguration for custom resources
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: custom-resource-validator
webhooks:
- name: custom.validator.example.com
  clientConfig:
    service:
      name: custom-validator-service
      namespace: webhook-system
      path: /validate-custom-resources
      port: 443
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["mycompany.com"]
    apiVersions: ["v1"]
    resources: ["mycustomresources"]
Webhook Flow - How It Works:
text
User creates Pod
    ↓
Kubernetes API Server receives request
    ↓
Calls Mutating Webhooks (if any)
    ↓ ← Your webhook server can modify the Pod
Calls Validating Webhooks (if any)  
    ↓ ← Your webhook server can accept/reject the Pod
Request is processed (created/rejected)
Complete Example: Pod Security Webhook
1. Webhook Server Deployment
yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: security-webhook
  namespace: webhook-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: security-webhook
  template:
    metadata:
      labels:
        app: security-webhook
    spec:
      containers:
      - name: webhook
        image: my-org/security-webhook:v1.0
        ports:
        - containerPort: 8443
        env:
        - name: TLS_CERT_FILE
          value: /etc/webhook/certs/tls.crt
        - name: TLS_KEY_FILE
          value: /etc/webhook/certs/tls.key
        volumeMounts:
        - name: webhook-certs
          mountPath: /etc/webhook/certs
          readOnly: true
      volumes:
      - name: webhook-certs
        secret:
          secretName: webhook-tls-cert
---
apiVersion: v1
kind: Service
metadata:
  name: security-webhook-service
  namespace: webhook-system
spec:
  selector:
    app: security-webhook
  ports:
  - port: 443
    targetPort: 8443
2. Validating Webhook Configuration
yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: security-policy-webhook
webhooks:
- name: security-policy.validator.example.com
  clientConfig:
    service:
      name: security-webhook-service
      namespace: webhook-system
      path: /validate
      port: 443
    caBundle: <base64-encoded-ca-bundle>
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  failurePolicy: Fail
  admissionReviewVersions: ["v1"]
  sideEffects: None
  timeoutSeconds: 5
3. Example Webhook Server Logic (Python)
python
from flask import Flask, request, jsonify
import base64
import json

app = Flask(__name__)

@app.route('/validate', methods=['POST'])
def validate_pod():
    admission_request = request.json
    pod = admission_request['request']['object']
    
    # Check security policies
    violations = []
    
    # Reject privileged containers
    for container in pod.get('spec', {}).get('containers', []):
        security_context = container.get('securityContext', {})
        if security_context.get('privileged'):
            violations.append(f"Container {container['name']} is privileged")
    
    # Check if pod should be rejected
    if violations:
        return jsonify({
            "response": {
                "uid": admission_request['request']['uid'],
                "allowed": False,
                "status": {"message": "; ".join(violations)}
            }
        })
    
    # Allow the pod
    return jsonify({
        "response": {
            "uid": admission_request['request']['uid'],
            "allowed": True
        }
    })
Types of Webhooks:
1. Validating Admission Webhooks
Purpose: Accept or reject requests

Use case: Security policies, compliance checks

Cannot modify the object

2. Mutating Admission Webhooks
Purpose: Modify objects before persistence

Use case: Default values, sidecar injection

Can modify the object

3. Conversion Webhooks
Purpose: Convert between API versions

Use case: Custom resource version conversion

When NOT to Use Webhooks:
Simple validation that can be done with OpenAPI schema

Performance-critical operations (adds latency)

When webhook availability could block cluster operations

For basic defaults that can be set with MutatingAdmissionWebhook

Best Practices:
1. Failure Policy
yaml
failurePolicy: Fail  # Reject if webhook fails
# OR
failurePolicy: Ignore  # Allow if webhook fails
2. Timeout Settings
yaml
timeoutSeconds: 5  # Don't block indefinitely
3. Side Effects
yaml
sideEffects: None  # Webhook has no side effects
# OR  
sideEffects: NoneOnDryRun  # No side effects on dry-run
In Summary:
Webhooks in Kubernetes are interceptors that allow custom external logic to validate or mutate API requests. They're like bouncers at a club (validating) or stylists (mutating) that can reject or modify requests before they're processed.

Webhook Servers are the actual applications that implement the validation/mutation logic, while Webhook Configurations tell Kubernetes when and where to call these servers!

