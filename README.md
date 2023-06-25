# public-scripts
Scripts I've made to make my life easier and hopefully yours too.

## k8s/install-kube-tools.sh
Use this to setup a brand new VM with everything necessary to create or join a k8s cluster! Follows the exact process already laid out by the [K8s](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/) and [containerd](https://github.com/containerd/containerd/blob/main/docs/getting-started.md) docs.
- Installs the latest versions of [containerd](https://github.com/containerd/containerd/releases/latest), [runc](https://github.com/opencontainers/runc/releases/latest), and [CNI plugins](https://github.com/containernetworking/plugins/releases/latest)
- Configures `containerd` to use the `systemd` cgroup
- Configures the required `sysctl` settings on the OS
- Installs the `kubeadm`, `kubectl`, and `kubelet` tools from the Google Cloud `apt` repo

**Note:** Currently, this script has only been tested on Debian 11.

### Usage:
```
./install-kube-tools.sh [-u]
  -u: undo all script operations, revert back to clean slate
```
