#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Verificar root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Este script debe ejecutarse como root${NC}"
    exit 1
fi

# Configuración
WIFI_IF="wlo1"  # Cambiar por tu interfaz WiFi
SUBNET="192.168.100"  # Misma subred que en hostpot.sh

# Función para listar dispositivos
listar_dispositivos() {
    echo -e "${BLUE}Dispositivos conectados:${NC}"
    
    # Obtener lista de clientes
    if [ -f "/var/lib/misc/dnsmasq.leases" ]; then
        echo -e "${CYAN}Direcciones asignadas:${NC}"
        cat /var/lib/misc/dnsmasq.leases | awk '{print $3" ("$2") - "$4}'
    fi
    
    echo -e "\n${CYAN}Conexiones activas:${NC}"
    ip neigh show dev $WIFI_IF | grep -v FAILED
}

# Función para limitar velocidad
limitar_velocidad() {
    echo -e "${BLUE}Limitación de velocidad${NC}"
    listar_dispositivos
    
    read -p "Ingrese la IP del dispositivo: " ip
    read -p "Velocidad máxima (ej: 100kbit): " velocidad
    
    # Eliminar reglas existentes
    tc qdisc del dev $WIFI_IF root 2>/dev/null
    tc qdisc add dev $WIFI_IF root handle 1: htb
    
    # Crear clase para limitación
    tc class add dev $WIFI_IF parent 1: classid 1:1 htb rate $velocidad
    tc filter add dev $WIFI_IF protocol ip parent 1:0 prio 1 u32 match ip dst $ip flowid 1:1
    
    echo -e "${GREEN}Velocidad limitada a $velocidad para $ip${NC}"
}

# Función para bloquear dispositivo
bloquear_dispositivo() {
    echo -e "${BLUE}Bloqueo de dispositivos${NC}"
    listar_dispositivos
    
    read -p "Ingrese la MAC del dispositivo a bloquear: " mac
    
    # Agregar a lista negra
    iptables -A INPUT -m mac --mac-source $mac -j DROP
    iptables -A FORWARD -m mac --mac-source $mac -j DROP
    
    echo "$mac" >> /etc/hostapd/mac_deny
    
    echo -e "${GREEN}Dispositivo $mac bloqueado${NC}"
}

# Función para desconectar dispositivo
desconectar_dispositivo() {
    echo -e "${BLUE}Desconexión de dispositivos${NC}"
    
    # Función mejorada para obtener MAC
    obtener_mac() {
        local ip=$1
        # Método 1: Desde dnsmasq.leases
        local mac=$(cat /var/lib/misc/dnsmasq.leases 2>/dev/null | grep "$ip" | awk '{print $2}')
        
        # Método 2: Desde arp
        [ -z "$mac" ] && mac=$(arp -n | grep "$ip" | awk '{print $3}')
        
        # Método 3: Desde ip neigh
        [ -z "$mac" ] && mac=$(ip neigh show | grep "$ip" | awk '{print $5}')
        
        echo "$mac"
    }

    # Listar dispositivos mejorado
    echo -e "${CYAN}Dispositivos conectados:${NC}"
    cat /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print NR". "$3" ("$2") - "$4}'
    
    read -p "Ingrese la IP del dispositivo a desconectar: " ip
    
    # Validar formato IP
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Formato de IP inválido${NC}"
        return 1
    fi
    
    # Obtener MAC correctamente
    client_mac=$(obtener_mac "$ip")
    if [ -z "$client_mac" ]; then
        echo -e "${RED}No se pudo obtener la MAC para $ip${NC}"
        echo -e "Prueba estos comandos manualmente:"
        echo -e "1. arp -n | grep $ip"
        echo -e "2. ip neigh show | grep $ip"
        return 1
    fi
    
    echo -e "${YELLOW}Desconectando $ip (MAC: $client_mac)...${NC}"
    
    # 1. Bloqueo con iptables (método más confiable)
    echo -e "${CYAN}→ Método 1: Bloqueando tráfico con iptables${NC}"
    iptables -A FORWARD -m mac --mac-source "$client_mac" -j DROP 2>/dev/null && \
    iptables -A INPUT -m mac --mac-source "$client_mac" -j DROP 2>/dev/null && \
    echo -e "${GREEN}✓ Reglas de bloqueo añadidas${NC}" || \
    echo -e "${YELLOW}✗ Error al añadir reglas iptables (puede ser normal con nftables)${NC}"
    
    # 2. Hostapd_cli (si está disponible)
    if command -v hostapd_cli >/dev/null 2>&1; then
        echo -e "\n${CYAN}→ Método 2: Enviando señal de desconexión via hostapd${NC}"
        hostapd_cli -i "$WIFI_IF" deauthenticate "$client_mac" 2>/dev/null && \
        echo -e "${GREEN}✓ Señal de desconexión enviada${NC}" || \
        echo -e "${YELLOW}✗ No se pudo conectar con hostapd (¿está corriendo?)${NC}"
    else
        echo -e "\n${YELLOW}→ hostapd_cli no está disponible${NC}"
    fi
    
    # 3. Alternativa con iw (para clientes conectados)
    echo -e "\n${CYAN}→ Método 3: Desautenticando con iw${NC}"
    iw dev "$WIFI_IF" station del "$client_mac" 2>/dev/null && \
    echo -e "${GREEN}✓ Dispositivo desautenticado${NC}" || \
    echo -e "${YELLOW}✗ No se pudo desautenticar (puede reconectarse)${NC}"
    
    echo -e "\n${GREEN}✔ Se han aplicado todas las medidas de desconexión para $ip ($client_mac)${NC}"
    echo -e "${YELLOW}Nota: El dispositivo puede reconectarse automáticamente${NC}"
}

# Función para monitorear tráfico
monitorear_trafico() {
    echo -e "${BLUE}Monitor de tráfico${NC}"
    echo -e "${YELLOW}Presione Ctrl+C para detener${NC}"
    
    if ! command -v iftop &> /dev/null; then
        echo -e "${RED}iftop no está instalado. Instálelo con:${NC}"
        echo "sudo apt install iftop"
        return
    fi
    
    iftop -i $WIFI_IF -n -N -P
}

# Menú principal
menu_principal() {
    clear
    echo -e "${BLUE}=== Gestor de Hotspot ===${NC}"
    echo -e "1. Listar dispositivos conectados"
    echo -e "2. Limitar velocidad de dispositivo"
    echo -e "3. Bloquear dispositivo"
    echo -e "4. Desconectar dispositivo"
    echo -e "5. Monitorear tráfico"
    echo -e "6. Salir"
    echo -n -e "${YELLOW}Seleccione una opción (1-6): ${NC}"
    
    read opcion
    case $opcion in
        1) listar_dispositivos ;;
        2) limitar_velocidad ;;
        3) bloquear_dispositivo ;;
        4) desconectar_dispositivo ;;
        5) monitorear_trafico ;;
        6) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}" ;;
    esac
    
    read -p "Presione Enter para continuar..."
    menu_principal
}

# Iniciar menú
menu_principal