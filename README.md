# Davinci Resolve Cloud Rendering

This project is an automated process for preparing the environment of a cloud rendering solution for Davinci Resolve.

# How it works

The approach is to create a network and two cloud instances connected to it, one for the rendering and one for transfering and managing the material and the data going in and out of the rendering instance:

- instance #1: a linux vps with 4 cores and 8 gigabytes of ram with attached block storage. This instance will serve a Samba share to be accessible from the render server and serve an HTTPS method (FileBrowser) for securely uploading files to the Samba share from the internet.

- instance #2: a windows 10/11 vps with 32 cores and 128 gigabytes of with a beefy GPU in graphics mode to handle the renders. it contains DaVinci resolve and has access to the Samba share.

the file data-server.sh will prepare linux vps for being a data server. by the following methodology:

- Install Docker
- Setup the attached block storage: format, create partition and mount it to /mnt/store
- Install and setup Samba and create a samba share inside mounted folder named sftp-samba
- Deploy FileBrowser with nginx and self-signed certs for secure HTTPS access to the folder from the internet. the server is accessible through port 443 on data the server ip.

### Note:
setup user credentials for FileBrowser on first run to secure the access to your data.

# Automating windows instance deployment
I've tried many time with powershell scripts that could be located in the ./drafts folder but could yet succeed to create a script that will automate the deployment of windows, setup DaVinci Resolve and mount the Samba share. any help on that matter is welcome.

so, the easy solution currently which also I haven't tried yet is to prepare and deploy the windows instance and take a snapshot to create an image to use for deployment direct on your cloud provider.

the steps are simply:

- Install Windows
- Install latest nVidia studio drivers
- Install DaVinci Resolve
- Mount Samba Share inside of windows


# Thoughts on this methodology
- The reason why I'm using a linux VPS to server the data is to reduce the usage of the windows machine. This way the we can only consume the resources that we need to upload the data and prepare our project for rendering with using expensive GPU rental on the windows instance.
- We can keep the data on the linux vps for later revisiting the same project, while terminating the GPU instance, we don't pay for the GPU when we are not using.
- The data is served with Samba: windows compatible protocol for easy management.
- a Terraform file or any IaaS method would be a good idea to automate the provisioning of the required infrastructure would be a nice add-on
- other methods to upload the data into the linux vps would be welcome, this way a user has the option to choose the best and most secure way in their opinion.
