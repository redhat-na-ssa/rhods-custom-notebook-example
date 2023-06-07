Custom Notebook Demo
====================

This repository demonstrates how to manage [Red Hat OpenShift Data Science](https://www.redhat.com/en/resources/openshift-data-science-brief) (RHODS) resources using a GitOps model with [OpenShift GitOps](https://www.redhat.com/en/technologies/cloud-computing/openshift/gitops) based on [ArgoCD](https://argo-cd.readthedocs.io/en/stable/).

The Point
---------

If you have a Data Science team who is separate from your Data Science Platform team, or if your Data Science team is particularly disciplined, and there's a desire to leverage OpenShift GitOps, or other GitOps-style management interfaces, to manage RHODS components for deployed clusters, then you may find the documentation for RHODS leaves some gaps in your knowledge. This repository is designed to mock-up a more production-grade environment and give you some ideas about how you might go about configuring and deploying Data Science Projects, Workbenches, and Data Connections in RHODS using a robust and scalable production deployment management process - rather than clicking around the GUI to configure your environment, and making repeatability more challenging.

Prerequisites
-------------

- `oc` and `make` in your `$PATH`
- A _fresh_ OpenShift cluster. Deconflicting the things that are deployed here for a real cluster should be done carefully, and this demo is designed to inspire - not to drive production.
  - Make sure that your cluster has enough available resources to support all of the deployments here. Two m5.xlarge work instances in AWS is not enough, as an example. I tested using a cluster with three m5.4xlarge instances, but that's overkill - I think two or three m5.2xlarge instances would work fine.
  - Note the RHODS requirements [here](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_science_self-managed/1.27/html/installing_openshift_data_science_self-managed_in_a_disconnected_environment/requirements-for-openshift-data-science-self-managed_install), but also add to that that your OpenShift integrated registry must be functional - which it is not in Bare Metal, VMWare, or `platform: None` UPI deployments. [The documentation](https://docs.openshift.com/container-platform/4.13/registry/configuring-registry-operator.html#image-registry-on-bare-metal-vsphere) can help you get that set up, if needed.
- Either a valid `creds.env` file with `CLUSTER`, `USER`, and `PASSWORD` defined or a valid KubeConfig file at a known path.
  - To make `creds.env`, you could run something like the following (substituting the values appropriately):
  ```shell
  cat << EOF > creds.env
  CLUSTER=https://<YOUR_CLUSTER_API_ENDPOINT>:6443
  USER=<YOUR_USER_NAME>
  PASSWORD=<YOUR_PASSWORD>
  EOF
  ```

Usage
-----

If you're using a creds.env file, run the following:

```shell
make
```

If you're using a KubeConfig, run the following instead:

```shell
make KUBECONFIG=/path/to/your/kubeconfig
```

Wait just a few moments for the terminal to return, and you should be able to log in to the ArgoCD instance to watch the rollout of RHODS, an S3 endpoint, and the customized notebook image and instance. To help you look up that endpoint, you can run:

```shell
make credentials # KUBECONFIG=/path/to/your/kubeconfig
```

> **Note**:
>
> That command won't return an endpoint URL if a service isn't installed yet, but it should list the URLs for GitOps, RHODS, and the custom notebook instance if they're finished deploying.

Exploring What Happened
-----------------------

A Data Science Project (DSP) is a RHODS abstraction that sits on top of the traditional OpenShift Project or Kubernetes Namespace. This extra layer of metadata uses traditional OpenShift constructs for isolation and RBAC, but allows the Data Science context to bubble up into the RHODS dashboard. Here, we deployed a DSP named "Notebook Demo" in the OpenShift Project "notebook-demo."

We deployed [Upstream MinIO](https://github.com/minio/minio) in its own namespace to serve some simple S3 storage, so we can use a Data Connection in RHODS without requiring a full [OpenShift Data Foundation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation) deployment (which you should definitely consider in production for its HA, DR, and flexible File/Block/Object storage capabilities). It's just easier for a demo, and gets us to the same S3 API no matter what the backing store is.

We deployed, into the Notebook Demo DSP, a Data Science Connection via a Kubernetes Secret, for our MinIO connection. This surfaces automatically in the RHODS dashboard appropriately.

We deployed a custom Notebook image that RHODS picks up right away and is available when creating new Workbenches or Notebooks from the interface, via an appropriately annotated ImageStream. The image being used for this notebook instance was built from the latest supported version of the Generic Data Science notebook that's included with RHODS (via an [ImageStreamTag](https://docs.openshift.com/container-platform/4.13/openshift_images/image-streams-manage.html) that was injected in the [BuildConfig](https://docs.openshift.com/container-platform/4.13/cicd/builds/understanding-buildconfigs.html)). This custom image definition exists [in this repository](demo/custom-notebook-image/Containerfile), and simply extends that base with a single package - LightGBM, a Gradient Boosting framework. That container image could have been built anywhere, as long as it ends up imported into the Data Science Project. In our case, relying on the latest supported Notebook images in our RHODS deployment, it's easiest if we use the BuildConfigs in this way to trigger automatic rebuilds as RHODS updates. Additionally, we are using [`pipenv`](https://pipenv.pypa.io/en/latest/) to manage dependencies in our image, to ensure repeatable behavior. This has a higher maintenance cost than allowing our Data Science team to `pip install` arbitrary libraries, but this is often worth it for the consistency benefits it offers to critical components that end up in our production stack.

Finally, we spawned a custom Notebook instance. We leveraged some RHODS features to define persistent storage for our Notebook, giving us some visibility into the connections between our Notebook instance, the persistent storage used to save ipynb and other files, and the connection to object storage through S3. We also opted into OAuth injection from RHODS, giving us some access control over who can reach the Notebook instance using Kubernetes RBAC - anyone who lacks permissions to run HTTP `GET` requests in this namespace against the `Notebook` object will not be able to log in. The most advanced customization of our Notebook occurred in the `volumeMounts`. It's a [requirement of the POSIX standard](https://man7.org/linux/man-pages/man7/shm_overview.7.html) that `/dev/shm` be provided as a tmpfs mount (a RAM-disk) for Inter-Process Communication in memory. The [use-case](https://www.semicolonandsons.com/code_diary/unix/what-is-the-usecase-of-dev-shm) is a guaranteed location that will persist files to disk to allow multiple processes to communicate over a high-bandwidth channel that follows file semantics. Many Machine Learning frameworks, like PyTorch, leverage this mechanism for Python multi-processing (as opposed to multi-threading) to enable a communication channel between separate processes that resides in memory. Kubernetes has a hard default on the size of the provided tmpfs at 64MiB, but [there are solutions](https://github.com/kubernetes/kubernetes/issues/28272) for explicitly requesting a differently-sized tmpfs. We have customized this Notebook with a 2GiB tmpfs mounted to `/dev/shm` - which is not a configuration that's exposed through the RHODS UI.

If you have the privileges to create new Namespaces in OpenShift (the lowest level of which is `self-provisioner`), you can create new DSPs. If you have the privileges to create new `Notebook` (and relatedAPIs, like PersistentVolumeClaims) instances in any given namespace, then you can create new Workbenches. You can even use our custom image in new Workbenches. If privileges are given to _view_ the Notebook instance we've created, though, you only have the permission to log into the Notebook and image we've provided here.

Validating Customizations
-------------------------

Once your Workbench is reachable, you can open the interface and import the python library that was installed by the on-cluster image build by running the following in a notebook or python console, just to show it's working:

```python
import lightgbm
dir(lightgbm)
```

That cell (or set of commands in the console) should run fine and show you the methods and classes exposed by the LightGBM library.

To validate that the deeper customizations to our Notebook instance took, evaluate `/dev/shm`'s state by spawning a new Terminal instance inside the Jupyter spawner (you can click the `+` next to the notebook or console tab in your Jupyter interface) and running the following:

```shell
mount | grep shm
```

You should see the size of `/dev/shm` as 2097152k - which, if you do the math, is 2GiB. This is enough for lots of work, and we can customize the size (or unconstrain it entirely) depending on what we need.

Closing
-------

Do not use this repository to deploy custom notebooks and images in your environment. Explore the manifests and understand how the APIs behind RHODS come together to meet your needs and expectations, and take the elements from it that are necessary to accomplish those within your existing platform. You have deep customization at your fingertips, thanks to the interoperable standards behind the open source communities powering RHODS. If you have questions about how to make RHODS fit your expectations, please talk to your sales team.
