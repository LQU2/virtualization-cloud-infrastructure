Connection Broker

The connection broker handles user logins and directs users to the correct virtual desktop. It decides which virtual machine a user connects to and keeps track of active sessions. In Azure Virtual Desktop and Amazon WorkSpaces the connection broker is managed by the provider. This fits under SaaS because customers do not manage the control plane themselves.

Desktop Pools

Desktop pools are groups of virtual desktops that users connect to. These may be persistent desktops that stay assigned to one user or non persistent desktops that reset after logout. In Azure Virtual Desktop and Amazon WorkSpaces the virtual machines run in the cloud environment and are configured by the customer. This fits under IaaS because the customer manages VM settings and resource sizing.

Session Hosts

Session hosts are the servers or virtual machines that run desktop sessions. In an on premises environment the organization installs the operating system and manages updates. In Azure Virtual Desktop session hosts run as Azure virtual machines. In Amazon WorkSpaces they run as cloud desktops. Customers still control configuration decisions so this mostly maps to IaaS.

Remote Display Protocol

The remote display protocol allows screen output with keyboard and mouse input to move between the user device and the virtual desktop. On premises VDI requires administrators to configure protocols such as RDP or HDX. In platforms such as Azure Virtual Desktop and Amazon WorkSpaces the provider manages the protocol service and performance optimization. This is closer to SaaS because customers do not control the protocol engine.

User Profile Management

User profile management stores user settings with personal data so the desktop stays consistent during each login. In an on premises environment administrators configure profile servers or roaming profiles. In Azure Virtual Desktop profile storage often uses managed services such as Azure Files. Amazon WorkSpaces offers similar managed storage options. This fits under PaaS because the provider manages the storage platform while the customer manages the stored data.

Image Management

Image management refers to creating and maintaining the master desktop image used for deployments. In on premises VDI the IT team patches and updates the image manually. In Azure Virtual Desktop and Amazon WorkSpaces the customer still prepares the base image while the provider supplies the infrastructure used to store and deploy it. This mostly fits under IaaS because the customer controls the operating system with installed software inside the image.
