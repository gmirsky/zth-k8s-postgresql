# Zero to hero: Kubernetes PostgreSQL cluster

Zero to Hero: A Kubernetes PostgreSQL cluster tutorial from begining to end.

NOTE: This is still a work in progress

Revision Date: `24-December-2023`

------

## Assumptions

This tutorial is being deployed on a single node local Kubernetes cluster using Docker Desktop Kubernetes. If you wish to use another Kubernetes micro environment like  Minikube, Kind, etc. you may need to make some adjustments to the code.

The commands below were tested in a Zsh/Bash command line environment. Some of the commands like base64 will be executed differntly in Windows and you will need to adjust accordingly.

## Prerequisites

Please install the below packages to your environment

### Kubectl

Kubectl should have been installed with Docker Desktop when the Kuberneteses option is enabled. If not see installing Kubectl](https://kubernetes.io/docs/tasks/tools/)

### Krew

The Cloud Native Kubectl plugin is needed to generate the Postgres Operator. [See installing Krew on how to install this plug in.](https://krew.sigs.k8s.io/docs/user-guide/setup/install/) 

### Helm

 [see installing Helm](https://helm.sh/docs/intro/install/)

### K9S 

K9S is optional but recommended.

[see installing K9S](https://k9scli.io/topics/install/)

### Base64

#### Linux

Install base64 (on Linux) is included in coreutils. Use your distribution's package manager to install coreutils.

#### Mac

Install base64 (on Mac) 

```bash
# Install base64
brew install base64
```

### Windows

Install base64 (on Windows) using PowerShell

```powershell
# Install base64
Install-Module -Name Base64
```

### pgAdmin 

??? To be taken out in favor of installing a pgAdmin Pod ????

[see installing pgAdmin](https://www.pgadmin.org/download/) to install pgAdmin on your system so you can access the PostgreSQL cluster.

## Install the cnpg plugin using Krew

```bash
# Install the Krew Kubectl plugin
kubectl krew install cnpg
```

```bash
# Check the cnpg plugin and check the version
kubectl cnpg version                                                                                     
Build: {Version:1.21.1 Commit:27f62cac Date:2023-11-03}
```

Updating krew and cnpg plugins (if plugins are already installed.)

```bash
# Update krew plugin
kubectl krew upgrade
```

```bash
# Update cnpg plugin
kubectl krew upgrade cnpg
```

## Starting off

Starting with a clean Kubernetes cluster, let's get an idea of what is running already in the cluster before we begin.

```bash
# See what is running in our Kubernetes cluseter
kubectl get  all --all-namespaces   

NAMESPACE     NAME                                         READY   STATUS    RESTARTS       AGE
kube-system   pod/coredns-5dd5756b68-57m9d                 1/1     Running   1 (39m ago)    45h
kube-system   pod/coredns-5dd5756b68-wb89s                 1/1     Running   1 (39m ago)    45h
kube-system   pod/etcd-docker-desktop                      1/1     Running   39 (39m ago)   45h
kube-system   pod/kube-apiserver-docker-desktop            1/1     Running   39 (39m ago)   45h
kube-system   pod/kube-controller-manager-docker-desktop   1/1     Running   39 (39m ago)   45h
kube-system   pod/kube-proxy-4nrg8                         1/1     Running   1 (39m ago)    45h
kube-system   pod/kube-scheduler-docker-desktop            1/1     Running   39 (39m ago)   45h
kube-system   pod/storage-provisioner                      1/1     Running   2 (39m ago)    45h
kube-system   pod/vpnkit-controller                        1/1     Running   1 (39m ago)    45h

NAMESPACE     NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
default       service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP                  45h
kube-system   service/kube-dns     ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   45h

NAMESPACE     NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   45h

NAMESPACE     NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
kube-system   deployment.apps/coredns   2/2     2            2           45h

NAMESPACE     NAME                                 DESIRED   CURRENT   READY   AGE
kube-system   replicaset.apps/coredns-5dd5756b68   2         2         2       45h
```

## Create namespaces

We will only need the dev namespace for this tutorial. The higher environments, qa, beta and prod are all optional.

```bash
# Create namespaces for dev, qa, beta and prod
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace qa --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace beta --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
```

```bash
# List out the namespaces in the kube
kubectl get namespaces --all-namespaces --show-labels                                                     

NAME              STATUS   AGE   LABELS
beta              Active   20s   kubernetes.io/metadata.name=beta
default           Active   45h   kubernetes.io/metadata.name=default
dev               Active   40s   kubernetes.io/metadata.name=dev
kube-node-lease   Active   45h   kubernetes.io/metadata.name=kube-node-lease
kube-public       Active   45h   kubernetes.io/metadata.name=kube-public
kube-system       Active   45h   kubernetes.io/metadata.name=kube-system
prod              Active   10s   kubernetes.io/metadata.name=prod
qa                Active   29s   kubernetes.io/metadata.name=qa
```

## Generate and install the CloudNativePG Operator

Generate the operator yaml manifest. The `-n` flag defines the namespace where the operator is deployed to and the replicas flag tells us how many replicas of the operator should be installed (note: number of operator replicas - not postgres instances). For our demonstration we will pick one node but in production we would likely have 3, one for each cloud availability zone in the region.

```bash
# Generate the YAML manifest to deploy
kubectl cnpg install generate -n devops-system --replicas 1 > operator-manifests.yaml
```

```bash
# Apply the YAML file to deploy the CloudNativePG Operator
# No namespace is required since it is coded in the generated YAML file
kubectl apply -f operator-manifests.yaml
```

```bash
# Check to see if the CloudNativePG Operator deployment deployed successfully
kubectl get deployment -n devops-system cnpg-controller-manager --show-labels
```

You should get output like this when the `cnpg-controller-manager` is available and ready:

```bash
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE   LABELS
cnpg-controller-manager   1/1     1            1           24s   app.kubernetes.io/name=cloudnative-pg
```

## Deploy a PostgreSQL Clusters

We will deploy two PostgreSQL clusters, one in the dev namespace and one in the qa namespace (optional if you are short on cumputing resources). The clusters will have a master and two replicas. One replica is for read-only transactions and the other replica is used by the continuous backup facilites.

Create Kubernetes secret for backups to Azure (Skip for now)

```bash
# Create a kubernetes secret in namespace dev to hold our Azure credentials
kubectl create secret generic azure-creds \
  --from-literal=AZURE_STORAGE_ACCOUNT=<storage account name> \
  --from-literal=AZURE_STORAGE_KEY=<storage account key> \
  --from-literal=AZURE_STORAGE_SAS_TOKEN=<SAS token> \
  --from-literal=AZURE_STORAGE_CONNECTION_STRING=<connection string>
```



```bash
kubectl create secret generic azure-creds -n dev --from-literal=AZURE_STORAGE_ACCOUNT="cloudnativebackup" --from-literal=AZURE_STORAGE_KEY="nLmbws7/WkprkH8/PE1EK57boMRQo9sbg+4yqj5cx5KdKoCPpozELzhMG3TFcmL2kSKX3+eKCCUh+AStaYWU/Q==" --from-literal=AZURE_STORAGE_SAS_TOKEN="?sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2024-01-22T00:46:59Z&st=2023-12-21T16:46:59Z&spr=https&sig=HEChGsSDFJFCEhKO%2FKPcnSJ6fph0l3gPAbqbiNIibJ8%3D" --from-literal=AZURE_STORAGE_CONNECTION_STRING="BlobEndpoint=https://cloudnativebackup.blob.core.windows.net/;QueueEndpoint=https://cloudnativebackup.queue.core.windows.net/;FileEndpoint=https://cloudnativebackup.file.core.windows.net/;TableEndpoint=https://cloudnativebackup.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2024-01-22T00:46:59Z&st=2023-12-21T16:46:59Z&spr=https&sig=HEChGsSDFJFCEhKO%2FKPcnSJ6fph0l3gPAbqbiNIibJ8%3D"
 
```



### Create Kubernetes secret for backups to AWS (Skip for now)

```bash
# Create a kubernetes secret in namespace dev to hold our AWS credentials
kubectl create secret generic aws-credentials -n dev \
  --from-literal=ACCESS_KEY_ID='<access key goes here>' \
  --from-literal=ACCESS_SECRET_KEY='<secret key goes here>'
```


```bash
kubectl create secret generic aws-credentials -n dev --from-literal=ACCESS_KEY_ID='AKIA2RLSJDYK6NE74ZEH' --from-literal=ACCESS_SECRET_KEY='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'
```

Now add a label to our secret with the AWS account the secret belongs to.

```bash
# Label the secret
kubectl label secret aws-creds -n dev "aws-account=566646271983"                                         
```

```bash
# Get the secrets in namespace dev
kubectl get secrets  -n dev  --show-labels                                                               

NAME        TYPE     DATA   AGE     LABELS
aws-creds   Opaque   2      6m15s   aws-account=566646271983
```


Verify that the keys were stored properly and can be decrypted.

```bash
# Verify that you can decrypt the AWS access key secret
kubectl get secret aws-creds -o 'jsonpath={.data.ACCESS_KEY_ID}' -n dev | base64 --decode

# Cerify that you can decrypt the AWS access secret key
kubectl get secret aws-creds -o 'jsonpath={.data.ACCESS_SECRET_KEY}' -n dev | base64 --decode
```

### Deploy cluster for namespace dev

```bash
# Deploy a Postgresql cluster into the dev namespace
kubectl apply -f cluster-example.yaml -n dev
```

```bash
# Check the status of the cluster
kubectl cnpg status -n dev cluster-example

# Check the status of the cluster with verbose on
kubectl cnpg status -n dev cluster-example -v
```

This is what you should see initially as output:

```bash
Cluster Summary
Primary server is initializing
Name:              cluster-example
Namespace:         dev
PostgreSQL Image:  ghcr.io/cloudnative-pg/postgresql:16.0
Primary instance:   (switching to cluster-example-1)
Status:            Setting up primary Creating primary instance cluster-example-1
Instances:         3
Ready instances:   0

Certificates Status
Certificate Name             Expiration Date                Days Left Until Expiration
----------------             ---------------                --------------------------

cluster-example-ca           2024-03-17 14:18:14 +0000 UTC  90.00
cluster-example-replication  2024-03-17 14:18:14 +0000 UTC  90.00
cluster-example-server       2024-03-17 14:18:14 +0000 UTC  90.00

Continuous Backup status
Not configured

Physical backups
Primary instance not found

Streaming Replication status
Primary instance not found

Unmanaged Replication Slot Status
No unmanaged replication slots found

Instances status
Name  Database Size  Current LSN  Replication role  Status  QoS  Manager Version  Node
----  -------------  -----------  ----------------  ------  ---  ---------------  ----

Error: container not found
```

This is what you should see when the cluster has been deployed:

```bash
kubectl cnpg status -n dev cluster-example                                                                                                                                               ─╯
Cluster Summary
Name:                cluster-example
Namespace:           dev
System ID:           7315093927430983701
PostgreSQL Image:    ghcr.io/cloudnative-pg/postgresql:16.1
Primary instance:    cluster-example-1
Primary start time:  2023-12-21 17:00:33 +0000 UTC (uptime 18m23s)
Status:              Cluster in healthy state
Instances:           3
Ready instances:     3
Current Write LSN:   0/8000000 (Timeline: 1 - WAL File: 000000010000000000000007)

Certificates Status
Certificate Name             Expiration Date                Days Left Until Expiration
----------------             ---------------                --------------------------
cluster-example-ca           2024-03-20 16:55:06 +0000 UTC  89.98
cluster-example-replication  2024-03-20 16:55:06 +0000 UTC  89.98
cluster-example-server       2024-03-20 16:55:06 +0000 UTC  89.98

Continuous Backup status
First Point of Recoverability:  Not Available
Working WAL archiving:          OK
WALs waiting to be archived:    0
Last Archived WAL:              000000010000000000000007   @   2023-12-21T17:11:04.891528Z
Last Failed WAL:                -

Physical backups
No running physical backups found

Streaming Replication status
Replication Slots Enabled
Name               Sent LSN   Write LSN  Flush LSN  Replay LSN  Write Lag  Flush Lag  Replay Lag  State      Sync State  Sync Priority  Replication Slot
----               --------   ---------  ---------  ----------  ---------  ---------  ----------  -----      ----------  -------------  ----------------
cluster-example-2  0/8000000  0/8000000  0/8000000  0/8000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active
cluster-example-3  0/8000000  0/8000000  0/8000000  0/8000000   00:00:00   00:00:00   00:00:00    streaming  async       0              active

Unmanaged Replication Slot Status
No unmanaged replication slots found

Managed roles status
No roles managed

Tablespaces status
No managed tablespaces

Instances status
Name               Database Size  Current LSN  Replication role  Status  QoS         Manager Version  Node
----               -------------  -----------  ----------------  ------  ---         ---------------  ----
cluster-example-1  29 MB          0/8000000    Primary           OK      BestEffort  1.22.0           docker-desktop
cluster-example-2  29 MB          0/8000000    Standby (async)   OK      BestEffort  1.22.0           docker-desktop
cluster-example-3  29 MB          0/8000000    Standby (async)   OK      BestEffort  1.22.0           docker-desktop
```

### Deploy cluster for namespace qa (optional)

You can skip this section if you are shor on computing resources

```bash
# Deploy a Postgresql cluster into the qa namespace
kubectl apply -f cluster-example.yaml -n qa
```

```bash
# Check the status of the cluster
kubectl cnpg status -n qa cluster-example -v
```

## Monitoring

### Install monitoring

```bash
# Check to see what Helm charts are in your local Helm repository
helm repo list

# Add the Prometheus Community Helm chart to your local Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Install Prometheus monitoring using the Helm chart we just added
helm upgrade --install -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/kube-stack-config.yaml prometheus-community prometheus-community/kube-prometheus-stack -n devops-system 

# Check to see if Prometheus is running correctly
kubectl --namespace devops-system get pods -l "release=prometheus-community"
```

```bash
# Forward port 9090 so we can access the Prometheus web site
kubectl port-forward -n devops-system svc/prometheus-community-kube-prometheus 9090 
```

In our case, the URL would be [localhost on port 9090](http://localhost:9090)

Hit Control-C to stop the port forwarding so we can proceed to the next steps

### Install monitoring rules

```bash
# Install CNPG sample Prometheus monotring rules
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/prometheusrule.yaml -n devops-system 
```

### Install Grafana dashboard

Graphana is installed with Prometheus. Below we will install a monitoring dashboard that provides comprehensive details on our clusters.

```bash
# Install Graphana so we can use dashboards to report Prometheus data
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/grafana-configmap.yaml -n devops-system 
```

```bash
# Forward the Graphana port so we can access the dashboard
kubectl port-forward -n devops-system svc/prometheus-community-grafana 3000:80
```

Log in with the user ID `admin` and the password `prom-operator` using the [localhost:3000](http://localhost:3000) URL and navigate to dashboards.

![dashboards](./images/dashboards.png)

Open the CloudNativePG dashboard.

![qa-monitoring](./images/qa-monitoring.png)

Scroll down and investigate the hundreds of parameters Prometheus captures about the PostgreSQL databases.

Prometheus will automatically pick up monitorng data from any database in the Kubernetes cluster that has the following stanza in its deployment YAML.

```YAML
  monitoring:
    enablePodMonitor: true
```

## Secrets

We can easily get the secrets from the YAML that we created the cluster with but in the even the deployment YAML is not available to you, you can retrieve the secrets from Kubernetes (provided you have the rights to do so).

In our cluster deplyment YAML we configured the sercrets for cluster-example-app-user for the application using the following YAML.

```yaml
apiVersion: v1
data:
  password: Q2hAbmdlTTNOb3chCg==
  username: YXBw
kind: Secret
metadata:
  name: cluster-example-app-user
type: kubernetes.io/basic-auth
```

The passwords are obfuscated using base64.

We did the same thing with cluster administrator (user id: postgres):

```yaml
apiVersion: v1
data:
  password: Q2hAbmdlTTNOb3chCg==
  # must always be postgres
  username: cG9zdGdyZXM=
kind: Secret
metadata:
  name: cluster-example-superuser
type: kubernetes.io/basic-auth
```

To get the above password we would use the following command:

```bash
echo Q2hAbmdlTTNOb3chCg== | base64 --decode                                                               
postgres
```

We can use the same command to decode the username too.

### Getting secrets from Kubernetes secrets

To log into the PostgreSQL cluster. We need to get the password from the Kubernetes secrets. Let's list all the secrets for the namespace dev. Each namespace has its own set of secrets.

```bash
# Get a listing of available Kubernetes secrets in the namespace
kubectl get secrets  -n dev 
```

We should get output like this:

```bash
NAME                          TYPE                       DATA   AGE
cluster-example-app-user      kubernetes.io/basic-auth   2      70m
cluster-example-ca            Opaque                     2      70m
cluster-example-replication   kubernetes.io/tls          2      70m
cluster-example-server        kubernetes.io/tls          2      70m
cluster-example-superuser     kubernetes.io/basic-auth   2      70m
```

The two secrets we are interested in are: `cluster-example-app-user`, `cluster-example-superuser`

### cluster-example-app-user credentials

To get the user id for the application user contained in `cluster-example-app-user` in namespace dev we would use the following command:

```bash
# Get the user id from cluster-example-app-user in namespace dev
kubectl get secret cluster-example-app-user -o 'jsonpath={.data.username}' -n dev | base64 --decode       
app%
```

**NOTE**: Always ignore the percent sign at the end of the line.

To get the password for the user app contained in `cluster-example-app-user` in namespace dev we would use the following command:

```bash
kubectl get secret cluster-example-app-user -o 'jsonpath={.data.password}' -n dev | base64 --decode       
postgres
```

### cluster-example-superuser credentials

#### cluster-example-superuser

To get the superuser id contained in `cluster-example-superuser` in namespace dev we would use the following command:

```bash
kubectl get secret cluster-example-superuser -o 'jsonpath={.data.username}' -n dev | base64 --decode
postgres%
```

**NOTE**: Always ignore the percent sign at the end of the line.

To get the password for the superuser contained in `cluster-example-superuser` in namespace dev we would use the following command:

```bash
kubectl get secret cluster-example-superuser -o 'jsonpath={.data.password}' -n dev | base64 --decode
postgres
```

Get the cluster services  in namespace dev.

```bash
# Get the services that belong to our cluster in namespace dev
kubectl get services -n dev -l cnpg.io/cluster=cluster-example                                           

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
cluster-example-r    ClusterIP   10.110.243.89   <none>        5432/TCP   4h28m
cluster-example-ro   ClusterIP   10.102.152.52   <none>        5432/TCP   4h28m
cluster-example-rw   ClusterIP   10.106.64.120   <none>        5432/TCP   4h28m

```

We want the read/write service which would be `cluster-example-rw`

### Ingress Controller (Work in progress)

NOTE: This section is still under development and debugging. Please go to the next section: Port-Forwarding and follow the instructions there.

**Important**: it is not advisable to port-forward ports from pods or services in production. A ingress controller should be used.

Make sure you configure `pg_hba` to allow connections from the Ingress.

```bash
# Add Ingress-Nginx to our local Helm repository
helm repo add ingress-nginx  https://kubernetes.github.io/ingress-nginx 

# List the Helm repos to verify that it was added
heml repo list
```



```bash
# Install the Nginx Ingress controller
helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx --namespace ingress-nginx --create-namespace 
```

```bash
# create a tcp-services configmap
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: tcp-services
  namespace: ingress-nginx
data:
  5432: dev/cluster-example-rw:5432
EOF
```



```bash
# cluster expose: add the port to the ingress-nginx service to expose it
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
    - name: postgres
      port: 5432
      targetPort: 5432
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
EOF
```

To do: add verification steps that the controller is up and running.

### Port Forwarding

Forward the `cluster-example-rw` service so that you can access it from your pgAdmin application.

```bash
# Forward the read/write service so it is accessible outside of the K8S cluster
kubectl port-forward service/cluster-example-rw 5432:5432 -n dev
```

### Connect to the database with pgAdmin

Once connected to pgAdmin click on the Add Server quick link.

In the General tab, for Name, put a meaningful name for you. Below we put cluster-example.

![register-server](./images/register-server.png)

On the Connection tab, for Hostname.address we put localhost. For Username put the super user name, postgres (or you could have put the user name app). For password supply the proper password. Hit save to connect and save the connection.

![connection](./images/connection.png)

After successful connection to the database you should see the navigation tree on the left hand side.

![sucessful-login](./images/sucessful-login.png)

## Miscellaneous 

### Getting the master pod

Since CloudNativePG can switch the primary pod, depending upon setup and environmental reasons, such as the primary pod malfuctions, you cannot assume the primary pod when the database was provisioned is still the primary node.

To find the primary pod for the database in namespace dev use the following command:

```bash
# Get the primary database pod 
kubectl get pods -o jsonpath={.items..metadata.name} -l cnpg.io/cluster=cluster-example,cnpg.io/instanceRole=primary -n dev
cluster-example-1%
```

