For a Kubernetes pod in Error state, you can check the logs using these commands:

1. Check the pod logs directly:
bash
kubectl logs pricer-app-85b554844b-gqvwr
2. If the pod crashed and you want previous container logs:
bash
kubectl logs pricer-app-85b554844b-gqvwr --previous
3. Get more detailed pod information:
bash
kubectl describe pod pricer-app-85b554844b-gqvwr
4. For real-time monitoring if the pod keeps restarting:
bash
kubectl logs pricer-app-85b554844b-gqvwr -f
5. Check all containers in the pod (if multi-container):
bash
kubectl logs pricer-app-85b554844b-gqvwr --all-containers=true
6. Check events in the namespace:
bash
kubectl get events --sort-by=.lastTimestamp
Most useful sequence for debugging:
bash
# First get detailed pod info
kubectl describe pod pricer-app-85b554844b-gqvwr

# Then check the logs
kubectl logs pricer-app-85b554844b-gqvwr

# If container already terminated, check previous instance
kubectl logs pricer-app-85b554844b-gqvwr --previous
The kubectl describe command will show you:

Events that occurred with the pod

Reason for failure

Restart count

Resource issues (if any)

Image pull errors

The kubectl logs will show you the application logs from the container itself, which usually contains the specific error causing the crash.