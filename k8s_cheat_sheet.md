
# The Complete Kubectl Command Reference

An exhaustive, command-by-command guide with syntax, flags, and practical examples for the Kubernetes professional.

---

## Index of Commands

*   `annotate`
*   `api-resources`
*   `api-versions`
*   `apply`
*   `attach`
*   `auth`
*   `autoscale`
*   `certificate`
*   `cluster-info`
*   `completion`
*   `config`
*   `cordon`
*   `cp`
*   `create`
*   `debug`
*   `delete`
*   `describe`
*   `diff`
*   `drain`
*   `edit`
*   `exec`
*   `explain`
*   `expose`
*   `get`
*   `kustomize`
*   `label`
*   `logs`
*   `patch`
*   `plugin`
*   `port-forward`
*   `proxy`
*   `replace`
*   `rollout`
*   `run`
*   `scale`
*   `set`
*   `taint`
*   `top`
*   `uncordon`
*   `version`
*   `wait`

---

### `annotate`

**Description:** Add or update the annotations of one or more resources.

**Syntax:** `kubectl annotate [--overwrite] (-f FILENAME | TYPE NAME) KEY_1=VAL_1 ... KEY_N=VAL_N`

**Flags:**
*   `--overwrite`: If true, allow annotations to be overwritten.
*   `-l, --selector`: Selector (label query) to filter on.
*   `--all`: Select all resources in the namespace.
*   `-f, --filename`: Filename, directory, or URL to files to use to specify the resource to annotate.

**Practical Examples:**

```bash
# Add an annotation to a pod
kubectl annotate pod my-pod description="My favorite pod"

# Overwrite an existing annotation on a deployment
kubectl annotate deployment my-deployment description="New description" --overwrite

# Annotate all pods in the current namespace
kubectl annotate pods --all author="John Doe"

# Remove an annotation (by appending a minus sign to the key)
kubectl annotate pod my-pod description-
```

---

### `api-resources`

**Description:** Print the supported API resources on the server.

**Syntax:** `kubectl api-resources`

**Flags:**
*   `--api-group`: Limit to a specific API group (e.g., `apps`, `storage.k8s.io`).
*   `--namespaced`: If true, shows only namespaced resources. If false, shows only cluster-wide resources.
*   `-o, --output`: Output format (`wide`, `name`).

**Practical Examples:**

```bash
# List all available API resources
kubectl api-resources

# List all resources in the 'apps' API group
kubectl api-resources --api-group=apps

# List all cluster-scoped (non-namespaced) resources
kubectl api-resources --namespaced=false

# List resources with their short names
kubectl api-resources -o wide
```

---

### `api-versions`

**Description:** Print the supported API versions on the server, in the form of `group/version`.

**Syntax:** `kubectl api-versions`

**Practical Examples:**

```bash
# List all supported API versions
kubectl api-versions
# Example Output: admissionregistration.k8s.io/v1, apps/v1, autoscaling/v2, ...
```

---

### `apply`

**Description:** Apply a configuration to a resource by filename or stdin. This is the primary command for declarative management.

**Syntax:** `kubectl apply -f FILENAME`

**Flags:**
*   `-f, --filename`: Filename, directory, or URL to files to use to create or update a resource.
*   `--dry-run`: If `client`, only print the object that would be sent, without sending it. If `server`, submit server-side request without persisting the resource.
*   `--prune`: Automatically delete resources that are no longer defined in the applied configuration.
*   `--force`: Force the replacement of a resource if a patch is not possible.

**Practical Examples:**

```bash
# Apply a single manifest file
kubectl apply -f ./pod.yaml

# Apply all manifest files in a directory
kubectl apply -f ./my-app-manifests/

# Apply manifests from a URL
kubectl apply -f https://raw.githubusercontent.com/kubernetes/website/main/content/en/examples/application/nginx-app.yaml

# See what changes would be made without actually applying them
kubectl apply -f ./deployment.yaml --dry-run=server

# Apply a directory and delete any resources in that namespace with the matching label that are not in the directory
kubectl apply -f ./my-app/ --prune -l app=my-app
```

---

### `attach`

**Description:** Attach to a running process in a container.

**Syntax:** `kubectl attach POD -c CONTAINER`

**Flags:**
*   `-c, --container`: Container name.
*   `-i, --stdin`: Pass stdin to the container.
*   `-t, --tty`: Allocate a TTY.

**Practical Examples:**

```bash
# Attach to a pod with a single container
kubectl attach my-pod -i -t

# Attach to a specific container in a multi-container pod
kubectl attach my-pod -c my-container
```

---

### `auth`

**Description:** Inspect authorization.

**Syntax:** `kubectl auth COMMAND`

**Subcommands:**
*   `can-i`: Checks if a user can perform a specific action.
*   `reconcile`: Reconciles RBAC policies.

**Practical Examples:**

```bash
# Check if I can create deployments in the current namespace
kubectl auth can-i create deployments

# Check if a specific service account can list secrets in another namespace
kubectl auth can-i list secrets --as=system:serviceaccount:dev:my-sa -n dev

# Check if I can perform an action cluster-wide
kubectl auth can-i create nodes --all-namespaces
```

---

### `autoscale`

**Description:** Creates a HorizontalPodAutoscaler (HPA) that automatically scales a resource.

**Syntax:** `kubectl autoscale (-f FILENAME | TYPE NAME | TYPE/NAME) [--min=MINPODS] --max=MAXPODS [--cpu-percent=CPU]`

**Flags:**
*   `--min`: The minimum number of replicas.
*   `--max`: The maximum number of replicas.
*   `--cpu-percent`: The target average CPU utilization (e.g., 80).
*   `--memory-request`: The target memory request utilization.

**Practical Examples:**

```bash
# Create an HPA for a deployment named 'my-app'
# It will scale between 2 and 10 replicas, targeting 80% CPU usage.
kubectl autoscale deployment my-app --min=2 --max=10 --cpu-percent=80
```

---

### `certificate`

**Description:** Manage certificates and CertificateSigningRequests (CSRs).

**Syntax:** `kubectl certificate approve|deny|describe CSR_NAME`

**Practical Examples:**

```bash
# View all CSRs
kubectl get csr

# Approve a pending CSR
kubectl certificate approve my-pending-csr

# Deny a pending CSR
kubectl certificate deny my-other-csr
```

---

### `cluster-info`

**Description:** Display cluster information.

**Syntax:** `kubectl cluster-info [dump]`

**Practical Examples:**

```bash
# Display the addresses of the master and services
kubectl cluster-info

# Dump the current cluster state to stdout (very verbose)
kubectl cluster-info dump

# Dump cluster state to a specific directory
kubectl cluster-info dump --output-directory=./cluster-state
```

---

### `completion`

**Description:** Generates shell completion scripts for `bash`, `zsh`, `fish`, or `powershell`.

**Syntax:** `kubectl completion SHELL`

**Practical Examples:**

```bash
# Generate bash completion script for the current shell
source <(kubectl completion bash)

# Add completion to your .bashrc file permanently
echo "source <(kubectl completion bash)" >> ~/.bashrc
```

---

### `config`

**Description:** Modify kubeconfig files.

**Syntax:** `kubectl config SUBCOMMAND`

**Subcommands:**
*   `view`: Display merged kubeconfig settings.
*   `get-contexts`: Describe one or many contexts.
*   `current-context`: Display the current-context.
*   `use-context`: Set the current-context in a kubeconfig file.
*   `set-cluster`, `set-credentials`, `set-context`: Define new entries.
*   `unset`: Remove entries.

**Practical Examples:**

```bash
# View your entire kubeconfig
kubectl config view

# List all available contexts
kubectl config get-contexts

# Get the name of the current context
kubectl config current-context

# Switch to a different context
kubectl config use-context my-other-cluster

# Set the namespace for the current context
kubectl config set-context --current --namespace=production
```

---

### `cordon`

**Description:** Mark a node as unschedulable.

**Syntax:** `kubectl cordon NODE`

**Practical Examples:**

```bash
# Prevent new pods from being scheduled on node-1
kubectl cordon node-1
```

---

### `cp`

**Description:** Copy files and directories between a container and the local filesystem.

**Syntax:** `kubectl cp <file-spec-src> <file-spec-dest>`

**Practical Examples:**

```bash
# Copy a file from a pod to your local machine
kubectl cp my-namespace/my-pod:/path/to/file.txt ./file.txt

# Copy a file from your local machine to a pod
kubectl cp ./local-file.txt my-namespace/my-pod:/path/to/remote-file.txt

# Copy to a specific container in a multi-container pod
kubectl cp ./local-file.txt my-pod:/path/to/file -c my-container
```

---

### `create`

**Description:** Create a resource from a file or from stdin (imperative).

**Syntax:** `kubectl create -f FILENAME` or `kubectl create <RESOURCE> <NAME> [OPTIONS]`

**Practical Examples:**

```bash
# Create a resource from a file (less common than 'apply')
kubectl create -f my-resource.yaml

# Create a new namespace
kubectl create namespace my-namespace

# Create a secret
kubectl create secret generic my-secret --from-literal=password='s3cr3t'

# Create a deployment (useful for quick tests)
kubectl create deployment nginx --image=nginx

# Create a service to expose a deployment
kubectl create service clusterip my-service --tcp=80:8080
```

---

### `debug`

**Description:** Create a debugging session for a workload or node.

**Syntax:** `kubectl debug (POD | TYPE/NAME | node/NODE_NAME) [FLAGS]`

**Practical Examples:**

```bash
# Create an interactive, ephemeral copy of a pod for debugging
kubectl debug my-pod -it --copy-to=my-debug-pod --image=busybox --share-processes

# Attach a debug container to a running pod
kubectl debug -it my-pod --image=busybox --attach

# Start a root shell on a node for debugging node-level issues
kubectl debug node/my-node -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11
```

---

### `delete`

**Description:** Delete resources by filenames, stdin, resources and names, or by resources and label selector.

**Syntax:** `kubectl delete (-f FILENAME | TYPE NAME | -l SELECTOR)`

**Flags:**
*   `--force`: Force immediate deletion. Use with extreme caution.
*   `--grace-period`: The period of time in seconds given to the resource to terminate gracefully. A value of 0 indicates immediate deletion.
*   `--all`: Delete all resources in the current namespace.

**Practical Examples:**

```bash
# Delete a pod by name
kubectl delete pod my-pod

# Delete resources defined in a file
kubectl delete -f ./pod.yaml

# Delete all pods with a specific label
kubectl delete pods -l app=my-app

# Delete all pods and services in the current namespace
kubectl delete pods,services --all

# Force delete a pod that is stuck terminating (DANGEROUS)
kubectl delete pod my-stuck-pod --grace-period=0 --force
```

---

### `describe`

**Description:** Show detailed state of one or more resources, including related events.

**Syntax:** `kubectl describe TYPE [NAME_PREFIX | -l SELECTOR]`

**Practical Examples:**

```bash
# Get all details about a specific pod, including events
kubectl describe pod my-pod

# Describe a node to see its taints, conditions, and resource usage
kubectl describe node my-node-1

# Describe all pods with a certain label
kubectl describe pods -l app=my-app

# Describe a deployment to see its rollout status and events
kubectl describe deployment my-deployment
```

---

### `diff`

**Description:** Diff live version against a would-be applied version.

**Syntax:** `kubectl diff -f FILENAME`

**Practical Examples:**

```bash
# See the differences between the running config and the one in my-deployment.yaml
kubectl diff -f my-deployment.yaml
```

---

### `drain`

**Description:** Drain a node in preparation for maintenance.

**Syntax:** `kubectl drain NODE [OPTIONS]`

**Flags:**
*   `--ignore-daemonsets`: Ignore DaemonSet-managed pods.
*   `--delete-emptydir-data`: Continue even if there are pods using emptyDir volumes.
*   `--force`: Continue even if there are pods not managed by a replication controller, job, or statefulset.

**Practical Examples:**

```bash
# Safely evict all pods from node-1
kubectl drain node-1 --ignore-daemonsets
```

---

### `edit`

**Description:** Edit a resource on the server.

**Syntax:** `kubectl edit TYPE/NAME`

**Practical Examples:**

```bash
# Open the live manifest for a deployment in your default editor
kubectl edit deployment my-deployment

# Edit a configmap
kubectl edit configmap my-config
```

---

### `exec`

**Description:** Execute a command in a container.

**Syntax:** `kubectl exec POD -c CONTAINER -- COMMAND [ARGS]`

**Flags:**
*   `-i, --stdin`: Pass stdin to the container.
*   `-t, --tty`: Allocate a TTY.

**Practical Examples:**

```bash
# Get an interactive shell in a running pod
kubectl exec -it my-pod -- /bin/bash

# Run a single command and see the output
kubectl exec my-pod -- ls /app

# Execute a command in a specific container of a multi-container pod
kubectl exec -it my-pod -c my-sidecar -- /bin/sh
```

---

### `explain`

**Description:** Get documentation for a resource and its fields.

**Syntax:** `kubectl explain RESOURCE_TYPE[.FIELD_PATH]`

**Practical Examples:**

```bash
# Get the documentation for the Pod resource
kubectl explain pod

# Get documentation for a specific field, like a container's spec
kubectl explain pod.spec.containers

# Drill down into nested fields
kubectl explain pod.spec.containers.livenessProbe.httpGet
```

---

### `expose`

**Description:** Create a Service to expose a deployment, replicaset, or pod.

**Syntax:** `kubectl expose DEPLOYMENT/NAME --port=PORT --target-port=TARGET_PORT`

**Flags:**
*   `--type`: The type of service to create (`ClusterIP`, `NodePort`, `LoadBalancer`).
*   `--port`: The port the service should serve on.
*   `--target-port`: The port on the container that the service should direct traffic to.

**Practical Examples:**

```bash
# Expose a deployment as a ClusterIP service
kubectl expose deployment my-app --port=80 --target-port=8080

# Expose a deployment as a NodePort service
kubectl expose deployment my-app --port=80 --target-port=8080 --type=NodePort
```

---

### `get`

**Description:** Display one or many resources.

**Syntax:** `kubectl get TYPE [NAME | -l SELECTOR]`

**Flags:**
*   `-o, --output`: Output format (`wide`, `yaml`, `json`, `jsonpath`, `custom-columns`).
*   `-A, --all-namespaces`: List resources in all namespaces.
*   `-w, --watch`: Watch for changes.
*   `--sort-by`: Sort by a JSONPath expression.

**Practical Examples:**

```bash
# List all pods in the current namespace
kubectl get pods

# List all pods in all namespaces with more details
kubectl get pods -A -o wide

# Get a specific pod's full YAML definition
kubectl get pod my-pod -o yaml

# List all deployments and services
kubectl get deployments,services

# Get the IP address of all pods
kubectl get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP

# Watch for new pods being created
kubectl get pods -w
```

---

### `kustomize`

**Description:** Build a kustomization target from a directory or URL.

**Syntax:** `kubectl kustomize <DIR>`

**Practical Examples:**

```bash
# Build the resources from a kustomization directory
kubectl kustomize ./my-kustomization/

# Apply the output of kustomize directly
kubectl apply -k ./my-kustomization/
```

---

### `label`

**Description:** Add or update the labels of one or more resources.

**Syntax:** `kubectl label [--overwrite] (-f FILENAME | TYPE NAME) KEY_1=VAL_1 ...`

**Practical Examples:**

```bash
# Add a label to a pod
kubectl label pod my-pod env=production

# Overwrite an existing label
kubectl label pod my-pod env=staging --overwrite

# Remove a label
kubectl label pod my-pod env-
```

---

### `logs`

**Description:** Print the logs for a container in a pod.

**Syntax:** `kubectl logs POD [-c CONTAINER]`

**Flags:**
*   `-f, --follow`: Follow the log stream.
*   `--previous`: Print logs for a previous instantiation of a container.
*   `--since`: Only return logs newer than a relative duration like `5s`, `2m`, or `1h`.
*   `--tail`: Lines of recent log file to display.

**Practical Examples:**

```bash
# Stream the logs from a pod
kubectl logs -f my-pod

# Get logs from a specific container
kubectl logs -f my-pod -c my-sidecar

# Get the last 100 lines of logs
kubectl logs my-pod --tail=100

# Get logs from the last 10 minutes
kubectl logs my-pod --since=10m

# View logs of a crashed container
kubectl logs my-pod --previous
```

---

### `patch`

**Description:** Update fields of a resource using a patch.

**Syntax:** `kubectl patch TYPE NAME -p 'PATCH'`

**Flags:**
*   `--type`: The type of patch being provided (`strategic`, `json`, `merge`).

**Practical Examples:**

```bash
# Update a container's image using a strategic merge patch
kubectl patch deployment my-app -p '{"spec":{"template":{"spec":{"containers":[{"name":"my-app-container","image":"new-image:1.2.3"}]}}}}'

# Add a new label using a JSON merge patch
kubectl patch pod my-pod --type merge -p '{"metadata":{"labels":{"new-label":"true"}}}'
```

---

### `plugin`

**Description:** Provides utilities for interacting with plugins.

**Syntax:** `kubectl plugin list`

**Practical Examples:**

```bash
# List all visible plugins
kubectl plugin list
```

---

### `port-forward`

**Description:** Forward one or more local ports to a pod.

**Syntax:** `kubectl port-forward TYPE/NAME [LOCAL_PORT:]REMOTE_PORT`

**Practical Examples:**

```bash
# Forward local port 8080 to port 80 on a pod
kubectl port-forward my-pod 8080:80

# Forward local port 9090 to port 80 on a service
kubectl port-forward svc/my-service 9090:80

# Listen on all local network interfaces
kubectl port-forward --address 0.0.0.0 my-pod 8080:80
```

---

### `proxy`

**Description:** Runs a proxy to the Kubernetes API server.

**Syntax:** `kubectl proxy [--port=PORT]`

**Practical Examples:**

```bash
# Run a proxy on the default port (8001)
kubectl proxy

# Now you can access the API directly
# curl http://localhost:8001/api/v1/namespaces/default/pods
```

---

### `replace`

**Description:** Replace a resource by filename or stdin.

**Syntax:** `kubectl replace -f FILENAME`

**Flags:**
*   `--force`: Force the replacement, deleting the old resource and creating a new one.

**Practical Examples:**

```bash
# Replace a resource based on a new YAML file. The resource must already exist.
kubectl replace -f ./my-pod-v2.yaml
```

---

### `rollout`

**Description:** Manage the rollout of a resource.

**Syntax:** `kubectl rollout (history|pause|resume|restart|status|undo) DEPLOYMENT/NAME`

**Practical Examples:**

```bash
# Watch the status of a deployment rollout
kubectl rollout status deployment/my-app

# View the history of a deployment
kubectl rollout history deployment/my-app

# Roll back to the previous version
kubectl rollout undo deployment/my-app

# Roll back to a specific revision
kubectl rollout undo deployment/my-app --to-revision=3

# Trigger a new rollout by restarting the deployment
kubectl rollout restart deployment/my-app
```

---

### `run`

**Description:** Create and run a particular image in a pod (imperative).

**Syntax:** `kubectl run NAME --image=IMAGE [OPTIONS]`

**Flags:**
*   `--image`: The image for the container to run.
*   `--port`: Port to expose.
*   `--env`: Environment variables to set.

**Practical Examples:**

```bash
# Create a single pod running nginx
kubectl run nginx --image=nginx

# Create a pod and open an interactive shell (for quick debugging)
kubectl run my-shell --rm -it --image=busybox -- /bin/sh
```

---

### `scale`

**Description:** Set a new size for a Deployment, ReplicaSet, or StatefulSet.

**Syntax:** `kubectl scale [--replicas=COUNT] (-f FILENAME | TYPE NAME)`

**Practical Examples:**

```bash
# Scale a deployment to 3 replicas
kubectl scale deployment my-app --replicas=3

# Scale a statefulset
kubectl scale statefulset my-db --replicas=5
```

---

### `set`

**Description:** Imperatively set specific fields on objects.

**Syntax:** `kubectl set (env|image|resources|selector|subject) ...`

**Practical Examples:**

```bash
# Update the image of a container in a deployment
kubectl set image deployment/my-app my-container=my-image:2.0

# Set an environment variable for all containers in a deployment
kubectl set env deployment/my-app ENV_VAR=new_value

# Set resource limits and requests
kubectl set resources deployment/my-app --limits=cpu=200m,memory=512Mi --requests=cpu=100m,memory=256Mi
```

---

### `taint`

**Description:** Update the taints on one or more nodes.

**Syntax:** `kubectl taint nodes NODE_NAME KEY_1=VAL_1:TAINT_EFFECT_1 ...`

**Taint Effects:**
*   `NoSchedule`: New pods won't be scheduled on the node unless they have a matching toleration.
*   `PreferNoSchedule`: The scheduler will try to avoid placing pods on the node.
*   `NoExecute`: Evicts running pods that don't tolerate the taint.

**Practical Examples:**

```bash
# Add a taint to a node that prevents scheduling
kubectl taint nodes node-1 app=blue:NoSchedule

# Remove a taint from a node
kubectl taint nodes node-1 app:NoSchedule-
```

---

### `top`

**Description:** Display resource (CPU/Memory) usage. Requires the Metrics Server to be installed.

**Syntax:** `kubectl top (node | pod) [NAME | -l SELECTOR]`

**Practical Examples:**

```bash
# Display CPU and memory usage for all nodes
kubectl top node

# Display CPU and memory usage for all pods in the current namespace
kubectl top pod

# Display usage for pods in all namespaces
kubectl top pod -A
```

---

### `uncordon`

**Description:** Mark a node as schedulable.

**Syntax:** `kubectl uncordon NODE`

**Practical Examples:**

```bash
# Allow pods to be scheduled on node-1 again
kubectl uncordon node-1
```

---

### `version`

**Description:** Print the client and server version information.

**Syntax:** `kubectl version`

**Flags:**
*   `--client`: Only print the client version.
*   `--short`: Print only the version number.

**Practical Examples:**

```bash
# Get client and server versions
kubectl version

# Get just the client version number
kubectl version --client --short
```

---

### `wait`

**Description:** Wait for a specific condition on one or many resources.

**Syntax:** `kubectl wait --for=CONDITION TYPE/NAME`

**Flags:**
*   `--for`: The condition to wait on (e.g., `delete`, `condition=Ready`).
*   `--timeout`: How long to wait.

**Practical Examples:**

```bash
# Wait for a pod to be in the 'Ready' state
kubectl wait --for=condition=Ready pod/my-pod --timeout=120s

# Wait for a job to complete
kubectl wait --for=condition=complete job/my-job

# Wait for a pod to be deleted
kubectl wait --for=delete pod/my-pod --timeout=60s
```
