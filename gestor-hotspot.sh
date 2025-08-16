#!/bin/bash

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Verificación de Root ---
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Este script debe ejecutarse como root${NC}"
    exit 1
fi

# <<< MEJORA: Recibir la interfaz WiFi como argumento del script principal >>>
if [ -z "$1" ]; then
    echo -e "${RED}Error: Se debe proporcionar la interfaz WiFi como argumento.${NC}"
    echo -e "Ejemplo: ./gestor-hotspot.sh wlan0"
    exit 1
fi
WIFI_IF="$1"

# --- Funciones ---

listar_dispositivos() {
    echo -e "${BLUE}Dispositivos conectados en la interfaz ${CYAN}$WIFI_IF${NC}:${NC}"
    if [ -s "/var/lib/misc/dnsmasq.leases" ]; then
        echo -e "${YELLOW}IP Asignada (MAC) - Nombre de Dispositivo${NC}"
        cat /var/lib/misc/dnsmasq.leases | awk '{print $3" ("$2") - "$4}'
    else
        echo -e "${RED}No hay dispositivos con IPs asignadas por dnsmasq.${NC}"
    fi
    echo -e "\n${YELLOW}Tabla de vecinos (ARP):${NC}"
    ip neigh show dev "$WIFI_IF" | grep -v FAILED
}

limitar_velocidad() {
    echo -e "${BLUE}--- Limitación de velocidad ---${NC}"
    listar_dispositivos
    echo ""
    read -p "Ingrese la IP del dispositivo: " ip
    read -p "Velocidad máxima (ej: 512kbit, 1mbit): " velocidad
    
    if [[ -z "$ip" || -z "$velocidad" ]]; then
        echo -e "${RED}IP y velocidad son campos obligatorios.${NC}"; return
    fi

    echo -e "${YELLOW}Aplicando límite de $velocidad a $ip...${NC}"
    # Eliminar reglas existentes para evitar conflictos
    tc qdisc del dev "$WIFI_IF" root 2>/dev/null
    # Crear nueva disciplina de cola (qdisc)
    tc qdisc add dev "$WIFI_IF" root handle 1: htb default 10
    # Crear clase principal con velocidad total alta
    tc class add dev "$WIFI_IF" parent 1: classid 1:1 htb rate 1000mbit
    # Crear clase específica para la IP limitada
    tc class add dev "$WIFI_IF" parent 1:1 classid 1:11 htb rate "$velocidad"
    # Crear filtro para dirigir el tráfico de la IP a la clase limitada
    tc filter add dev "$WIFI_IF" protocol ip parent 1:0 prio 1 u32 match ip dst "$ip" flowid 1:11
    
    echo -e "${GREEN}✓ Velocidad limitada a $velocidad para $ip${NC}"
}

bloquear_dispositivo() {
    echo -e "${BLUE}--- Bloqueo de dispositivo por MAC ---${NC}"
    listar_dispositivos
    echo ""
    read -p "Ingrese la MAC del dispositivo a bloquear: " mac

    if [ -z "$mac" ]; then echo -e "${RED}La MAC no puede estar vacía.${NC}"; return; fi

    echo -e "${YELLOW}Bloqueando $mac...${NC}"
    iptables -I FORWARD -m mac --mac-source "$mac" -j DROP
    
    echo -e "${GREEN}✓ Dispositivo $mac bloqueado a nivel de red (iptables).${NC}"
    echo -e "${YELLOW}Nota: El bloqueo se perderá al reiniciar el hotspot o el PC.${NC}"
}

# <<< NUEVA FUNCIÓN: Desbloquear dispositivo >>>
desbloquear_dispositivo() {
    echo -e "${BLUE}--- Desbloqueo de dispositivo por MAC ---${NC}"
    echo -e "${CYAN}Reglas de bloqueo activas:${NC}"
    iptables -L FORWARD -v -n | grep "MAC"
    echo ""
    read -p "Ingrese la MAC del dispositivo a desbloquear: " mac

    if [ -z "$mac" ]; then echo -e "${RED}La MAC no puede estar vacía.${NC}"; return; fi

    echo -e "${YELLOW}Intentando desbloquear $mac...${NC}"
    iptables -D FORWARD -m mac --mac-source "$mac" -j DROP 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Regla de bloqueo para $mac eliminada.${NC}"
    else
        echo -e "${RED}✗ No se encontró una regla de bloqueo para $mac.${NC}"
    fi
}


desconectar_dispositivo() {
    echo -e "${BLUE}--- Desconexión forzada de dispositivo ---${NC}"
    listar_dispositivos
    echo ""
    read -p "Ingrese la MAC del dispositivo a desconectar: " mac

    if [ -z "$mac" ]; then echo -e "${RED}La MAC no puede estar vacía.${NC}"; return; fi
    
    echo -e "${YELLOW}Intentando desconectar $mac...${NC}"

    if command -v hostapd_cli &> /dev/null; then
        hostapd_cli -i "$WIFI_IF" deauthenticate "$mac"
        echo -e "${GREEN}✓ Comando de desautenticación enviado vía hostapd_cli.${NC}"
    else
        iw dev "$WIFI_IF" station del "$mac"
        echo -e "${GREEN}✓ Comando de desconexión enviado vía iw.${NC}"
    fi
    echo -e "${YELLOW}Nota: El dispositivo puede intentar reconectarse inmediatamente.${NC}"
    echo -e "${YELLOW}Para un bloqueo permanente, use la opción 'Bloquear dispositivo'.${NC}"
}

monitorear_trafico() {
    if ! command -v iftop &> /dev/null; then
        echo -e "${RED}Error: iftop no está instalado.${NC}"
        echo -e "Para instalarlo en Ubuntu/Debian: sudo apt install iftop"
        return
    fi
    echo -e "${BLUE}Iniciando monitor de tráfico en ${CYAN}$WIFI_IF${NC} (Presiona 'q' para salir)${NC}"
    iftop -i "$WIFI_IF"
}

# Menú principal
menu_gestor() {
    clear
    echo -e "${BLUE}=== Gestor de Dispositivos de Hotspot ===${NC}"
    echo -e "Interfaz gestionada: ${CYAN}$WIFI_IF${NC}\n"
    echo -e "1. Listar dispositivos conectados"
    echo -e "2. Limitar velocidad de un dispositivo"
    echo -e "3. Bloquear un dispositivo (por MAC)"
    echo -e "4. Desbloquear un dispositivo (por MAC)"
    echo -e "5. Desconectar un dispositivo (temporalmente)"
    echo -e "6. Monitorear tráfico del hotspot"
    echo -e "7. Volver al menú principal"
    echo -n -e "${YELLOW}Seleccione una opción (1-7): ${NC}"
    
    read -r opcion
    case $opcion in
        1) listar_dispositivos ;;
        2) limitar_velocidad ;;
        3) bloquear_dispositivo ;;
        4) desbloquear_dispositivo ;;
        5) desconectar_dispositivo ;;
        6) monitorear_trafico ;;
        7) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}" ;;
    esac
    
    echo ""
    read -p "Presione Enter para continuar..."
    menu_gestor
}

# Iniciar menú
menu_gestor