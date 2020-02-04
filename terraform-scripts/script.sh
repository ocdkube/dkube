#!/bin/bash

###########################################
#                                         #
#             DKUBE EKS SCRIPT            #
#                                         #
###########################################

#######REQUIRED######
EKS_core_name=dkube-eks-test                    #Base name of your cluster
ip=99                                           #First 8-bit field value IPv4
pem=dkube-qa.pem                                #aws pem file to access cluster
ami="ami-08819fa70d3983bc6"                     #AMI-id of EKS Image
instance_type="m5a.4xlarge"                     #Instance type for your cluster
region=us-west-2                                #Region for your aws cluster
max_cluster_nodes=10                            #Maximum number of managed node groups per cluster
num_cluster_nodes=1                             #Number of nodes desired for current cluster



#######ADVANCED(When required user will modify based on setup)#######
k8s_version=1.14                                  #Kubernetes version
EKS_cluster_username=ubuntu                       #Username of the eks cluster
DISTRO=ubuntu                                     #Choose one of ubuntu/centos
DKUBEVERSON="1.4.3"                               #version of dkube to be installed
dkubeuser=user123                                 #Username for dkube
dkubepass=user123                                 #password for dkube user
installer_user_passwd='your setup password'       #Needed only if setup requires password on sudo permission


key=$( echo $pem | cut -d. -f1)
installer_username=`whoami`
platform=eks

center(){
  BOLD='\033[1m'
  NORMAL='\e[21m'
  NONE='\033[00m'
  GREEN='\033[38;5;155m'
  text="$*"
  printf "${GREEN}${BOLD}%*s${NORMAL}${NONE}\n" $(( ($(tput cols) + ${#text}) / 2)) "$text"
}

display_help() {
  NC='\e\033[00m'
  center "EKS SCRIPT USAGE"
  printf "Please update the variables as per usage"
  printf "%-100s${NC}\n" "EKS_core_name:               Base name of your cluster"
  printf "%-100s${NC}\n" "ip:                          First 8-bit field value IPv4"
  printf "%-100s${NC}\n" "pem:                         aws pem file to access cluster"
  printf "%-100s${NC}\n" "instance_type:               Instance type for your cluster"
  printf "%-100s${NC}\n" "region:                      Region for your aws cluster"
  printf "%-100s${NC}\n" "max_cluster_nodes:           Maximum number of managed node groups per cluster"
  printf "%-100s${NC}\n" "num_cluster_nodes:           Number of nodes desired for current"
  printf "%-100s${NC}\n" "installer_user_passwd:       Needed only if setup requires password on sudo permission"
  printf "%-100s${NC}\n" "dkubeuser:                   Username for dkube"
  printf "%-100s${NC}\n" "dkubepass:                   password for dkube user"
  exit $1
}

if [[ "$*" == *help* || "$*" == *-h* ]];then
  display_help
fi

echo $installer_user_passwd | sudo -S chmod 400 $pem
echo $installer_user_passwd | sudo -S cp install $HOME

#checking for root or not
if [ $(id -u) = "0" ]; then
          export PATH=$PATH:$HOME/bin
fi

#checking awscli installed or not
command -v aws
if [[ "${?}" -ne 0 ]];then
        echo "awscli not installed"
        echo "Installing aws cli ... "
        echo $installer_user_passwd | sudo -S  apt-get -y install awscli
        echo "please configure awscli and install aws-iam-authenticator https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html"
        exit 0
fi

#Untar the tar file. i.e terraform script
echo $installer_user_passwd | sudo -S tar -xvf eks-script3.tar

if [[ -e terraform_0.12.9_linux_amd64.zip ]];then
  echo $installer_user_passwd | sudo -S unzip terraform_0.12.9_linux_amd64.zip
  if [[ "${?}" -ne 0 ]];then
        echo "Something went wrong !! File terraform_0.12.9_linux_amd64.zip not unzipped."
        exit 1
  fi
  echo $installer_user_passwd | sudo -S mv terraform eks-getting-started
  if [[ "${?}" -ne 0 ]];then
        echo "Something went wrong !! Could not move file terraform into eks-getting-started directory."
        exit 1
  fi
fi

#Changed to working directory
echo $installer_user_passwd | sudo -S chown -R ${installer_username}:${installer_username} eks-getting-started
cd eks-getting-started


#Changed all resuorce name in terraform script
sed -i -e "s/demo/$EKS_core_name-&/g" -e "/version *= \"[0-9.]*\"/s/\"[0-9.]*\"/\"$k8s_version\"/" eks-cluster.tf
sed -i "s/demo/$EKS_core_name-&/g" variables.tf
sed -i -e "s/demo/$EKS_core_name-&/g" -e "/image_id *= \"ami-[a-zA-Z0-9]*\"/s/\"ami-[a-zA-Z0-9]*\"/\"$ami\"/" -e "/instance_type *= \"[a-zA-Z0-9.]*\"/s/\"[a-zA-Z0-9.]*\"/\"$instance_type\"/" -e "/key_name *= \"[a-zA-Z0-9-]*\"/s/\"[a-zA-Z0-9-]*\"/\"$key\"/" -e "/max_cluster_nodes *= [0-9]/s/[0-9]/$max_cluster_nodes/" -e "/num_cluster_nodes *= [0-9]/s/[0-9]/$num_cluster_nodes/" eks-worker-nodes.tf
sed -i "s/demo/$EKS_core_name-&/g" outputs.tf
sed -i "s/1.12/$k8s_version/g" variables.tf
sed -i "s/\"us-west-2\"/\"$region\"/" providers.tf
sed -i -e "s/demo/$EKS_core_name-&/g" -e "s/10.0.0.0\/16/$ip.0.0.0\/16/" -e "s/\"10.0.\${count.index}.0\/24\"/\"$ip.0.\${count.index}.0\/24\"/" vpc.tf
echo $installer_user_passwd | sudo -S  rm -rf terraform.tfstate terraform.tfstate.backup
#Init Terraform
./terraform init
touch result.txt
#Apply Terraform
./terraform apply -auto-approve -no-color |  tee result.txt
if [[ "${?}" -ne 0 ]];then
  echo "Something went wrong !! terroform apply Failed !!"
  exit 1
fi

#Read terraform apply output in yaml file
sed -n '/config_map_aws_auth =/,/kubeconfig/p'  result.txt > config_map_aws_auth.yaml
sed -i '1d; $d' config_map_aws_auth.yaml
sed -i '1d' config_map_aws_auth.yaml
sed -n '/kubeconfig =/,//p'  result.txt > kubeconfig
sed -i 's/\x1b\[[0-9;]*m//g' kubeconfig
sed -i '1d' kubeconfig
sed -i '1d' kubeconfig
if [ ! -d $HOME/.kube ];then
  mkdir  $HOME/.kube
fi
echo $installer_user_passwd | sudo -S chown -R $installer_username:$installer_username $HOME/.kube
cp kubeconfig $HOME/.kube/config

sleep 3m
#Apply the yaml file , what we got above
kubectl apply -f config_map_aws_auth.yaml
if [[ "${?}" -ne 0 ]];then
        echo "Something went wrong !! Applying config_map_aws_auth.yaml Failed !!"
        exit 1
fi

#Check for Docker if not installed, installed it
command -v docker
if [[ "${?}" -ne 0 ]];then
  VERSIONSTRING="5:18.09.2~3-0~ubuntu-bionic"
  echo "Docker does not exist\n"
  echo "installing Docker\n"
  sudo apt-get remove docker docker-engine docker.io containerd runc
  sudo apt-get -y update
  sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo apt-key fingerprint 0EBFCD88
  sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  sudo apt-get -y update
  sudo apt-get install docker-ce=$VERSIONSTRING docker-ce-cli=$VERSIONSTRING containerd.io
fi
echo $installer_user_passwd | sudo -S systemctl start docker
echo $installer_user_passwd | sudo -S docker login -u lucifer001 -p lucifer@dkube
echo $installer_user_passwd | sudo -S docker pull ocdr/dkubeadm:1.4.2
echo $installer_user_passwd | sudo -S docker run --rm -t -v $HOME/.dkube:/root/.dkube ocdr/dkubeadm:1.4.2 init
echo $installer_user_passwd | sudo -S cp $HOME/install $HOME/.dkube/install
echo $installer_user_passwd | sudo -S cp ../$pem $HOME/.dkube/
echo $installer_user_passwd | sudo -S chown -R $installer_username:$installer_username $HOME/.dkube

#Check for kubectl.if not installed, installed it
command -v kubectl
if [[ "${?}" -ne 0 ]]; then
  echo "Kubectl does not exist\n"
  echo "Installing kubectl\n"
  curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
  chmod +x ./kubectl
  sudo mv ./kubectl /usr/local/bin/kubectl
  kubectl version
fi

sleep 150s
nodes=$(kubectl get no -o wide | awk '{if (NR!=1) {print $1}}')
if [[ "${?}" -ne 0 ]];then
        echo "Something went wrong !!"
        exit 1
fi
nodes=($nodes)
echo "$nodes"
externalip=$(kubectl get no -o wide | awk '{if (NR!=1) {print $7}}')
externalip=($externalip)
echo "$externalip"
internalip=$(kubectl get no -o wide | awk '{if (NR!=1) {print $6}}')
internalip=($internalip)
echo "$internalip"

cd $HOME/.dkube

#sed dkube.ini
sudo sed -i "/^\[REQUIRED\]/,/^PLATFORM=/s/=.*/=$platform/" dkube.ini
sudo sed -i "/^DISTRO=/s/DISTRO=.*/DISTRO=$DISTRO/" dkube.ini
sudo sed -i "/^USERNAME=/s/USERNAME=.*/USERNAME=$dkubeuser/" dkube.ini
sudo sed -i "/^PASSWORD=/s/PASSWORD=.*/PASSWORD=$dkubepass/" dkube.ini
sudo sed -i "s/DKUBE_NODE_NAME=.*/DKUBE_NODE_NAME=$nodes/" dkube.ini
sudo sed -i "s/STORAGE_DISK_NODE=.*/STORAGE_DISK_NODE=$nodes/" dkube.ini
cat dkube.ini

#sed k8s.ini
sudo sed -i "/^\[deployment\]/,/^provider=/s/=.*/=$platform/" k8s.ini
sudo sed -i "/^distro=/s/distro=.*/distro=$DISTRO/" k8s.ini
for((i=0; i<${#externalip[@]};++i));do sed -i "/^\[nodes\]/,/^#/s/#.*/${externalip[i]} ${internalip[i]}/" k8s.ini; done
sudo sed -i "/^\[ssh-user\]/,/^user=/s/=.*/=$EKS_cluster_username/" k8s.ini
cat k8s.ini

echo $installer_EKS_cluster_username_passwd | sudo -S  cp $HOME/.kube/config $HOME/.dkube/kubeconfig
echo $installer_user_passwd | sudo -S chown -R $installer_username:$installer_username $HOME/.dkube/kubeconfig

#Make Passwordless
if [[ ! $externalip[0] =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  for((i=0; i<${#externalip[@]};++i));do sudo cat ssh-rsa.pub|sudo ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR -o UserKnownHostsFile=/dev/null -i ${pem} ubuntu@${externalip[i]} "cat - >> .ssh/authorized_keys"; done
  if [[ "${?}" -ne 0 ]];then
        echo "Something went wrong !!.Passwordless SSH Failed"
        exit 1
  fi
  echo "Passwordless SSH set ..."
fi

#Dkube Install
cd $HOME/.dkube
ls -larth $HOME/.dkube
sudo chmod 400 $HOME/.dkube/$pem
sudo ./install
