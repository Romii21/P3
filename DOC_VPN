## Tâches :

**Prioritaire (Romain)** WEB - Mettre en place un serveur WEB INTERNE
	- Utilisation de la solution suivante :
		- **Apache**
			- https://httpd.apache.org/
			- https://github.com/apache/httpd
	- Site pour les collaborateurs de l'entreprise

## 1. Contexte et Objectifs

Dans le cadre du projet d'infrastructure EcoTech Solutions, nous avons déployé un serveur web interne.

- **Fonction :** Héberger le portail Intranet (informations collaborateurs, liens utiles, support).
    
- **Public cible :** Uniquement les collaborateurs connectés au réseau interne (LAN) ou via VPN.
    
- **Sécurité :** Le serveur est isolé dans le **VLAN 220 (Infrastructure)** et n'est pas exposé directement à Internet (pas de NAT entrant).
    

## 2. Fiche d'Identité Technique

|**Paramètre**|**Valeur**|**Justification**|
|---|---|---|
|**Nom d'hôte**|`ECO-BDX-EX07`|Respect de la nomenclature serveur (EX)|
|**OS**|Debian 12 (Bookworm)|Stabilité et standard de l'industrie|
|**Type**|Conteneur LXC (Proxmox)|Légèreté et démarrage rapide par rapport à une VM|
|**Adresse IP**|`10.20.20.7`|Plan d'adressage Infrastructure|
|**Masque (CIDR)**|`/27` (255.255.255.224)|Segmentation réseau stricte|
|**Passerelle**|`10.20.20.1`|Interface du routeur pour le VLAN 220|
|**VLAN ID**|`220`|Zone Serveurs / Infrastructure|
|**DNS**|`10.20.20.5`|Contrôleur de Domaine (AD)|

## 3. Procédure d'Installation Réalisée

### Phase 1 : Déploiement sur Proxmox

Création d'un conteneur (CT) non privilégié avec les ressources suivantes :

- 1 vCore CPU / 1024 Mo RAM / 8 Go Disque.
    
- Configuration réseau sur le pont `vmbr0` avec le **Tag VLAN 220** pour assurer l'appartenance au bon réseau.
    

### Phase 2 : Configuration Système

- **Langue :** Passage du clavier en AZERTY (`dpkg-reconfigure keyboard-configuration`).
    
- **Accès distant (SSH) :**
    
    - Installation du service : `apt install openssh-server`
        
    - Autorisation du compte root : Modification de `/etc/ssh/sshd_config` (`PermitRootLogin yes`).
        
    - Test de connexion réussi depuis le poste d'administration : `ssh root@10.20.20.7`.
        

### Phase 3 : Service Web Apache

- **Installation :** `apt install apache2 -y`.
    
- **Personnalisation :** Remplacement de la page par défaut (`/var/www/html/index.html`) par une page chartée "EcoTech Solutions" incluant les informations de statut du serveur.
    

## 4. Tests de Validation

- **Service :** La commande `systemctl status apache2` retourne un statut **active (running)**.
    
- **Flux HTTP :** L'accès via un navigateur client sur le réseau (`http://10.20.20.7`) affiche correctement la page d'accueil Intranet.
    
- **Flux SSH :** L'administration à distance est fonctionnelle.
    

---
## Site WEB interne
### Liste commande :

#### Apache (root)

**Base**
- `apt update && apt upgrade`
- `apt install apache2 -y`
- `systemctl status apache2`
**SSH**
- `apt install openssh-server -y
**Utilisateur**
- `adduser "infra"`
- `usermod -aG sudo infra`
**Site**
- `rm /var/www/html/index.local`
- `sudo /var/www/html/index.local`
	- Site Infra ou Web "html"
### Apache (user)

**Info Page**
- `sudo apt install curl`
- `curl -I http://Ton_IP`
	- Type Serveur + Version + OS
- `sudo nano /etc/apache2/conf-available/security.conf`
	- `ServerTokens Prod`
	- `ServerSignature Off`
- `sudo systemctl restart apache2`
- `sudo systemctl status apache2`
- `curl -I http://Ton_IP`
	- Type Serveur
**SSH**
- `sudo nano /etc/ssh/sshd_config`
	- PermitRootLogin No

## Gestion pare-feu

### Flux

- **Interface WAN (Entrée) :**
    
    - _Protocole :_ UDP.
        
    - _Port :_ 1194.
        
    - _Source :_ Any (ou restreint aux IP des prestataires si connues).
        
- **Interface OpenVPN (Interne) :**
    
    - _Source :_ Réseau Tunnel (`10.60.80.0/24`).
        
    - _Destination :_ Réseau `10.0.0.0/8` (L'ensemble de l'infra).
        
    - _Note :_ On peut restreindre ici si on veut empêcher le VPN d'atteindre certains VLANs sensibles (ex: VLAN Admin), mais la sécurité applicative (AD) suffit généralement.

### Concept

- Les **prestataire** utiliseront une **connexion VPN** pour **rentrer dans le réseau**.
- Une fois dans le réseau ils ne pourront accéder à rien sauf si il se connecte à leurs compte AD (double verrous).

### Mise en pratique 

#### Phase 1 : Cryptographie 

- Protocole : **SSL/TSL**

**Etape 1 :**

- Création de l'**autorité de certification** `EcoTech-CA` :

	- Sur **pfSense :
		- System :
			- Certificate :
				- Authorities
	
	- Descriptions :
		- **Descriptive name :** `EcoTech-CA`
		- **Method :** `Create an internal Certificate Authority`
		- **Key length :** `2048` (Standard actuel)
		- **Digest Algorithm :** `SHA256`
		- **Country Code :** `FR`
		- **State/Province :** `Gironde`
		- **City :** `Bordeaux`
		- **Organization :** `EcoTech`
		- **Organizational Unit :** `DSI`

**Etape 2** :

- Création du **certificat** du serveur VPN :

	- Sur **pfSense** :
		- System :
			- Certificates :
				- Certificates

	- Descriptions :
		- **Method :** `Create an internal Certificate Authority`
		- **Descriptive name :** `EcoTech-VPN-Server-Cert`
		- **Certificat Authority** : `EcoTech-CA`
		- **LifeTime** : `398`
		- **Key length :** `2048` (Standard actuel)
		- **Digest Algorithm :** `SHA256`
		- **Common Name** : `vpn.ecotech-solutions.fr`
		- **Certificat Type** : `Server Certificate` (Point essentiel de la configuration)

#### Phase 2 : Le Tunnel VPN

- Configuration du services avec **Wizards** :

	- Sur **pfSense** :
		- VPN :
			- OpenVPN :
				- Wizards

- **Configuration et Certificats** :

	- **Type of serveur** : `Local User Access` (mdp vérifié sur la base locale du pfSense)
	- **Certificat Authority** : `EcoTech-CA`
	- **Certificat** : `EcoTech-VPN-Server-Cert`

- **Configuration du réseau** :

	- Descriptions :
		- **Description** : `VPN-Prestataire`
		- **Protocol** : `UDP on IPv4 only`
		- **Interface** : `WAN`
		- **Local Port** : `1194`
		- **IPv4 Tunnel Network** : `10.150.0.0/24` (SAS VPN)
		- **Redirect Local Network** : ✅ (Le trafic internet du prestataire est filtré par notre pare-feu)
		- **IPv4 Local Network** : `10.0.0.0/8`
		- **Concurrent Connections** : `10`
		- **Dynamic IP** : ✅
		- **Topology** : `Subnet`

- **Configuration du DNS** :

	- Descriptions :
		- **DNS Default Serveur** : `ecotech.local`
		- **DNS Server 1** : `10.20.20.5` (AD principal)
		- **DNS Server 2** : `10.20.20.6` (AD secondaire)

- **Configuration du Pare-Feu** :

	- Descriptions :
		- **Firewal Rule** : ✅ (Permet la connexion à ce tunnel VPN)
		- **OpenVPN rule** : ✅ (Permet de se déplacer dans le réseau)

#### Phase 3 : Les utilisateurs 

- Sur **pfSense** :
	- System :
		- User Manager :
			- Users

- **Ajout d'un Utilisateur** :

	- Descriptions :
		- **Username** : `zafernandez_ubihard`
		- **Password** : `Azerty1*`
		- **Full Name** : `Zara Fernandez UBIHard`
		- **Certificate** : ✅
		- **Descriptive Name** : `zara_fernandez_ubihard`
		- **Certificate Authority** : `EcoTech-CA`

- **Ajout d'un Utilisateur Admin** :

	- Descriptions :
		- **Username** : `ecotech_admin`
		- **Password** : `Azerty1*`
		- **Full Name** : `Adminstrateur EcoTech`
		- **Certificate** : ✅
		- **Descriptive Name** : `ecotech_admin`
		- **Certificate Authority** : `EcoTech-CA`

" Nous aurions pu créer un second serveur VPN pour les Administrateurs mais, je préfère la solution de connecter ce compte dans notre serveur existant avec une IP fixe ici `10.60.80.200` "

- sur **pfSense** : 
	- VPN :
		- OpenVPN :
			- Client Specific Overrides

- **Orientation vers un IP précis** :

	- Descriptions:
		- **Descriptions** : `IP fixe Administrateur VPN`
		- **Common Name** : `ecotech_admin`
		- **IPv4 Tunnel Network** : `10.60.80.200/24`

#### Phase 4 : Exportation de la Connexion

**Mise à niveau de pfSense**

- Avant d'effectuer l'export, vérifier que le **paquet additionnel** est bien installé.

	- Sur **pfSens** : 
		- System :
			- Package Manager :
				- Available Packages
	
		- **Search term** : export
			- Téléchargement du paquet

- Téléchargement des fichiers de **configuration VPN**

	- Sur **pfSense** :
		- VPN :
			- OpenVPN
				- Client Export

- **Configuration du fichier à exporter** :

	- Descriptions :
		- **Host Name Resolution** : `Interface IP Address` (Avec la config 10.0.0.3)

#### Phase 5 : Le client distant 

- Sur le **PC distant** le prestataire aura **OpenVPN** d'installer et configuré.
- Pour les tests la machine `Test-VPN` sera directement sur le réseau WAN avec l'adresse IP `10.0.0.4/29`

#### Phase 6 : Règles pour les prestataires

- Règles pour le compte **Admin** :

	- Descriptions :
		- **Action** : `Pass`
		- **Protocol** : `Any`
		- **Source** : `Single Host or Alias` -> `10.60.80.200`
		- **Destination** : `Any`
		- **Description** : `FULL ACCESS ADMIN`

- Règles pour les **utilisateurs** en quatre temps :

	* Descriptions règle 1 (Règle AD) : 
		- **Action :** `Pass`		    
		- **Protocol :** `TCP/UDP` (Important : les deux !)		    
		- **Source :** `Network` -> tape `10.60.80.0` / `24`		    
		- **Destination :** `Single Host or Alias` -> tape `10.20.20.5`		    
		- **Destination Port Range :** Laisse sur `any` (ou vide).		    
		- **Description :** `Acces AD`

	* Descriptions règle 2 (Serveurs WEB) : 
		- **Action :** `Pass`		    
		- **Protocol :** `TCP` 		    
		- **Source :** `Network` -> tape `10.60.80.0` / `24`		    
		- **Destination :** `Single Host or Alias` -> tape `10.20.20.7`		    
		- **Destination Port Range :** 
			- From :`HTTP (80)`
			- To : `HTTPS (443)`
		- **Description :** `Acces Intranet WEB`

	* Descriptions règle 3 (Navigation Internet) : 
		- **Action :** `Pass`		    
		- **Protocol :** `TCP/UDP` 		    
		- **Source :** `Network` -> tape `10.60.80.0` / `24`		    
		- **Destination :** `Any`		    
		- **Destination Port Range :** 
			- From :`HTTP (80)`
			- To : `HTTPS (443)`
		- **Description :** `Acces Internet`

	* Descriptions règle 4 (Blocage) : 
		- **Action :** `Block`		    
		- **Protocol :** `Any` 		    
		- **Source :** `Any`		    
		- **Destination :** `Any`		    
		- **Description :** `Bloque le reste`
