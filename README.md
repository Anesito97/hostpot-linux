# hostpot-linux
Crear Alias para el Script hotspot.sh
Para crear un alias que te permita ejecutar hostpot.sh fácilmente con sudo desde cualquier lugar, sigue estos pasos:

1. Primero verifica la ubicación exacta del script
bash
ls -l /home/anesito/hostpot/hostpot.sh
2. Edita tu archivo de configuración de alias
Abre tu archivo .bashrc o .zshrc (dependiendo de tu shell):

bash
nano ~/.bashrc
3. Añade este alias al final del archivo
bash
alias hotspot='sudo /home/anesito/hostpot/hostpot.sh'
4. Guarda los cambios y aplica la configuración
bash
source ~/.bashrc
5. Verifica que el alias funciona
bash
type hotspot
Deberías ver algo como:

text
hotspot is aliased to `sudo /home/anesito/hostpot/hostpot.sh'
6. Ahora puedes usar el comando fácilmente
bash
hotspot
(Esto ejecutará automáticamente sudo /home/anesito/hostpot/hostpot.sh)

Solución alternativa más robusta
Si prefieres una solución más permanente y profesional:

Crea un enlace simbólico en /usr/local/bin:

bash
sudo ln -s /home/anesito/hostpot/hostpot.sh /usr/local/bin/hotspot
Dale permisos de ejecución:

bash
sudo chmod +x /usr/local/bin/hotspot
Ahora puedes ejecutarlo simplemente con:

bash
sudo hotspot
Para eliminar el alias si lo necesitas
Edita de nuevo tu .bashrc:

bash
nano ~/.bashrc
Elimina la línea del alias y guarda

Recarga la configuración:

bash
source ~/.bashrc
ahora necesito pues recopilar todos los pasos todas las copsas que hay que instalar todo para ponerlo en mi README.md y asi en otro momento poder tener una instalacion facil
Guía Completa de Instalación y Configuración del Hotspot WiFi
📋 Requisitos Previos
Sistema operativo Linux (probado en Ubuntu/Debian)

Acceso de superusuario (sudo)

Conexión a Internet para instalar dependencias

🔧 Instalación de Dependencias
Ejecuta estos comandos para instalar todos los paquetes necesarios:

bash
sudo apt update
sudo apt install -y \
    hostapd \
    dnsmasq \
    iptables \
    iw \
    iproute2 \
    aircrack-ng \
    iftop \
    tcptrack \
    net-tools
📂 Estructura de Archivos
text
/home/anesito/hostpot/
├── hostpot.sh          # Script principal del hotspot
├── gestor-hotspot.sh   # Gestor de dispositivos conectados
└── README.md           # Este archivo de documentación
⚙️ Configuración del Sistema
Detener servicios que pueden interferir:

bash
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager
Permitir que hostapd y dnsmasq inicien al arrancar:

bash
sudo systemctl unmask hostapd
sudo systemctl enable hostapd dnsmasq
Configurar el forwarding de IP:

bash
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
🛠️ Configuración de los Scripts
Hacer los scripts ejecutables:

bash
chmod +x /home/anesito/hostpot/hostpot.sh
chmod +x /home/anesito/hostpot/gestor-hotspot.sh
Crear alias para fácil acceso (añadir al final de ~/.bashrc):

bash
alias hotspot='sudo /home/anesito/hostpot/hostpot.sh'
alias gestor-hotspot='sudo /home/anesito/hostpot/gestor-hotspot.sh'
Recargar la configuración del shell:

bash
source ~/.bashrc
🔄 Reiniciar Servicios Necesarios
bash
sudo systemctl restart dhcpcd
sudo systemctl restart dnsmasq
sudo systemctl restart hostapd
🚀 Uso Básico
Iniciar el hotspot:

bash
hotspot
Gestionar dispositivos conectados:

bash
gestor-hotspot
Opciones disponibles:

Limitar velocidad de dispositivos

Bloquear dispositivos no deseados

Monitorear tráfico en tiempo real

🛑 Restablecer Configuración
Para detener el hotspot y restaurar la configuración normal:

bash
sudo tc qdisc del dev wlo1 root 2>/dev/null
sudo systemctl stop hostapd dnsmasq
sudo systemctl start NetworkManager
📊 Comandos Útiles para Diagnóstico
Comando	Descripción
iwconfig	Ver interfaces inalámbricas
ifconfig	Ver configuraciones de red
iw dev wlo1 station dump	Ver dispositivos conectados
tc -s qdisc show dev wlo1	Ver limitaciones de ancho de banda
arp -a	Ver tabla ARP