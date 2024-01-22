# Login to Azure
az login

# Create Resource Group
az group create -l EastUS -n az-k8s-pg-rg

# (Linux/Mac) Find your external IP address for the az deployment command
dig @resolver3.opendns.com myip.opendns.com +short

# (Windows) Find your external IP address for the az deployment command
$(Resolve-DnsName myip.opendns.com -Server resolver3.opendns.com).IPAddress

# Deploy template with in-line parameters (place your IP address in the authorizedIPRanges parameter)
az deployment group create -g az-k8s-pg-rg \
    --template-file main.json \
    --parameters \
	resourceName=az-k8s-poc \
	managedNodeResourceGroup=az-k8s-poc-mrg \
	agentCount=1 \
	upgradeChannel=stable \
	JustUseSystemPool=true \
	osDiskType=Managed \
	osDiskSizeGB=32 \
	authorizedIPRanges="[\"108.29.92.98/32\"]" \
	ingressApplicationGateway=true

# Get credentials for your new AKS cluster & login (interactive)
az aks get-credentials -g az-k8s-pg-rg -n aks-az-k8s-poc
kubectl get nodes


# Delete AKS cluster
az aks delete -g az-k8s-pg-rg -n aks-az-k8s-poc --yes --no-wait 