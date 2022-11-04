#!bin/bash
echo "COMIENZO DE SCRIPT. Aut: Ángel Suárez Pérez"

echo "---------------------------------------------------------"

#Lo primero que vamos a hacer es comprobar que existe la imagen bullseye-base.qcow2
if [ -f /var/lib/libvirt/images/compbullseyebase.qcow2 ]
then
    echo "La imagen solicitada existe! Procediendo con la ejecución del script"
else
    echo "La imagen 'bullseye-base.qcow2' no existe"
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"
#Crea una imagen nueva, que utilice bullseye-base.qcow2 como imagen base y tenga 5 GiB de tamaño máximo. Esta imagen se denominará maquina1.qcow2.
echo "----- Creando imagen maquina1.qcow2 -----"
if [ -f /var/lib/libvirt/images/maquina1.qcow2 ]
then
    echo "La imagen ya está creada"
else
    echo "La imagen no está creada, procedemos a crearla"
    qemu-img create -f qcow2 -b compbullseyebase.qcow2 maquina1.qcow2 5G &>/dev/null
    if [ $? = 0 ]
    then
        echo "Imagen creada correctamente"
    else
        echo "Problemas al crear la imagen maquina1"
    fi
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Redimensionar sistema de ficheros
echo "----- Redimensionar sistema de ficheros -----"
cp maquina1.qcow2 newmaquina1.qcow2 &> /dev/null
virt-resize --expand /dev/sda1 maquina1.qcow2 newmaquina1.qcow2 &> /dev/null
if [ $? = 0 ]
then
    echo "Redimensión del sistema de ficheros realizada correctamente!"
else
    echo "Problemas al redimensionar el sistema de ficheros"
fi
rm maquina1.qcow2 && mv newmaquina1.qcow2 maquina1.qcow2 &> /dev/null
echo "---------------------------------------------------------"
echo -e "\n"

#Crea una red interna de nombre intra con salida al exterior mediante NAT que utilice el direccionamiento 10.10.20.0/24.
#Contenido de /etc/libvirt/qemu/networks/intra.xml
echo "----- Creando red interna 'intra' -----"
echo "<network>
<name>intra</name>
<bridge name='virbr50'/>
<forward/>
<ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
        <range start='10.10.20.2' end='10.10.20.254'/>
    </dhcp>
</ip>
</network>"  > intra.xml

sleep 3

if [ -f /etc/libvirt/qemu/networks/intra.xml ]
then
    echo "La red intra ya está definida"
else
    virsh -c qemu:///system net-define intra.xml &>/dev/null
    if [ $? = 0 ]
    then
        echo "Red intra definida correctamente"
    else
        echo "Problemas al definir red intra"
    fi
fi
echo "Iniciando red intra"
virsh -c qemu:///system net-start intra &>/dev/null
virsh -c qemu:///system net-autostart intra &>/dev/null
if [ $? = 0 ]
then
    echo "Red intra configurada para autoiniciar"
else
    echo "Problemas al configurar red intra como autoinicio"
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Crea una máquina virtual (maquina1) conectada a la red intra, con 1 GiB de RAM, que utilice como disco raíz maquina1.qcow2 y que se inicie automáticamente. Arranca la máquina. Modifica el fichero /etc/hostname con maquina1.
echo "----- Procedemos a la creación de la máquina virtual maquina1 -----"
virt-install --connect qemu:///system --virt-type kvm --name maquina1 --disk path=maquina1.qcow2 --import --memory 1024 --vcpus 1 --network network=intra --noautoconsole &>/dev/null
if [ $? != 0 ]
then
    echo "La máquina maquina1 ya está creada en el sistema"
    echo "Iniciando maquina1..."
    virsh -c qemu:///system start maquina1 &> /dev/null
    sleep 30
else
    echo "Máquina maquina1 creada correctamente"
fi
virsh -c qemu:///system autostart maquina1 &>/dev/null
sleep 35
dirip=$(sudo virsh -c qemu:///system domifaddr maquina1 | grep -oE "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | head -n 1)
sudo echo "Realizando cambios en el hostname de la maquina1..."
echo "Ip que ha recibido la máquina: " $dirip
ssh -i id_ecdsa debian@$dirip -o "StrictHostKeyChecking no" "sudo -- bash -c 'echo "maquina1" > /etc/hostname'" &>/dev/null
if [ $? = 0 ]
then
    echo "Hostname de la máquina cambiado correctamente"
else
    echo "Problemas al cambiar el hostname de la máquina virtual"
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Crea un volumen adicional de 1 GiB de tamaño en formato RAW ubicado en el pool por defecto
echo "----- Creamos volumen adicional de 1GiB -----"
if [ -f /var/lib/libvirt/images/voladicional ]
then
    echo "El volumen voladicional ya se encuentra creado en /var/lib/libvirt/images. Proseguimos con el script"
else
    virsh -c qemu:///system vol-create-as default voladicional --format raw 1GB &>/dev/null
    if [ $? = 0 ]
    then
        echo "Volumen voladicional creado correctamente"
    else
        echo "Hemos tenido problemas para crear el volumen voladicional"
    fi
sleep 3
fi
echo "---------------------------------------------------------"
echo -e "\n"

#Una vez iniciada la MV maquina1, conecta el volumen a la máquina, crea un sistema de ficheros XFS en el volumen y móntalo en el directorio /var/www/html. Ten cuidado con los propietarios y grupos que pongas, para que funcione adecuadamente el siguiente punto.
echo "----- Conectamos el volumen adicional a la máquina virtual -----"
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/voladicional vda --targetbus virtio --driver=qemu --type disk --subdriver raw --persistent &>/dev/null
if [ $? = 0 ]
then
    echo "Volumen voladicional asociado correctamente"
else
    echo "Hemos tenido problemas para asociar el volumen voladicional a la maquina1"
fi
sleep 20
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'apt install dosfstools &>/dev/null'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'mkfs.xfs -f /dev/vda &>/dev/null'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'mkdir -p /var/www/html'"

ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'mount /dev/vda /var/www/html'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'chown -R www-data:www-data /var/www/html'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'chmod -R 755 /var/www/html'"

ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'chmod 646 /etc/fstab'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'echo "/dev/vda /var/www/html xfs defaults 0 0" >> /etc/fstab'"
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"


#Instala en maquina1 el servidor web apache2. Copia un fichero index.html a la máquina virtual.
echo "----- Instalación y configuración de apache2 -----"
echo "Instalando apache2..."
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'apt install apache2 -y &>/dev/null'"
if [ $? = 0 ]
then
    echo "Apache2 instalado correctamente!"
    ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'echo "Ángel Suárez Pérez. Funcionamiento de Apache2" > index.html'"
    ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'mv index.html /var/www/html/'"
        if [ $? = 0 ]
    then
        echo "Fichero index.html creado y añadido a la ruta /var/www/html correctamente!"
    else
        echo "Hemos tenido problemas al crear el fichero index.html."
    fi
else
    echo "No hemos podido instalar apache2."
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Muestra por pantalla la dirección IP de máquina1. Pausa el script y comprueba que puedes acceder a la página web.
echo "-- Mostrar ip de la máquina y script pausado --"
echo "IP de la máquina virtual maquina1: " $dirip
read -p "Pausando script, introduce 'S' para continuar... - " variable1
while [ $variable1 != "S" ]
do
    read -p "Valor introducido incorrecto, SCRIPT PAUSADO, introduce 'S' para continuar... - " variable1
done
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Instala LXC y crea un linux container llamado container1.
echo "----- Instalación y creación de contenedor LXC -----"
echo "Instalando LXC..."
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'apt install lxc -y' &> /dev/null"
if [ $? = 0 ]
then
    echo "LXC instalado correctamente!"
    echo "Creando contenedor LXC..."
    ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'lxc-create -n container1 -t debian -- -r bullseye' &> /dev/null"
    if [ $? = 0 ]
    then
        echo "Contenedor LXC (container1) creado correctamente!"
    else
        echo "Hemos tenido problemas para crear el contenedor LXC container1."
    fi
else
    echo "Hemos tenido problemas al instalar el paquete LXC, por lo tanto no podemos crear el contenedor."
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Añade una nueva interfaz a la máquina virtual para conectarla a la red pública (al punte br0).
echo "----- Añadiendo nueva interfaz a la máquina virtual -----"
virsh -c qemu:///system shutdown maquina1 &>/dev/null
if [ $? = 0 ]
then
    echo "Apagando máquina virtual..."
else
    echo "Problemas para apagar la máquina virtual"
fi
sleep 20
virsh -c qemu:///system attach-interface maquina1 bridge br0 --model virtio --config &>/dev/null
sleep 20
virsh -c qemu:///system start maquina1 &>/dev/null
if [ $? = 0 ]
then
    echo "Arrancando la máquina virtual tras realizar cambios en las interfaces. Espere..."
else
    echo "Problemas para arrancar la máquina virtual"
fi
sleep 40

ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'chmod 646 /etc/network/interfaces'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'echo "auto ens9" >> /etc/network/interfaces'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'echo "iface ens9 inet dhcp" >> /etc/network/interfaces'"
ssh -i id_ecdsa debian@$dirip "sudo -- bash -c 'systemctl restart networking'"
sleep 25
echo "---------------------------------------------------------"
echo -e "\n"

#Muestra la nueva IP que ha recibido.
echo "-- IP recibida por la máquina --"
ssh -i id_ecdsa debian@$dirip "ip a show ens9 |  grep -oP 'inet \K[\d.]+'"
sleep 5
echo "---------------------------------------------------------"
echo -e "\n"

#Apaga maquina1 y auméntale la RAM a 2 GiB y vuelve a iniciar la máquina.
echo "----- Apagando máquina1 y aumentando RAM a 2GiB -----"
echo "Apagando maquina1..."
virsh -c qemu:///system shutdown maquina1 &> /dev/null
sleep 10
virsh -c qemu:///system setmaxmem maquina1 2G --config &> /dev/null
if [ $? = 0 ]
then
    echo "Actualizando memoria de la máquina virtual..."
else
    echo "Hemos tenido problemas para aumentar la memoria de la máquina"
fi
virsh -c qemu:///system setmem maquina1 2G --config &> /dev/null
if [ $? = 0 ]
then
    echo "Memoria de la máquina aumentada a 2G!"
else
    echo "Hemos tenido problemas para aumentar la memoria de la máquina"
fi
sleep 5
echo "Iniciando máquina1..."
virsh -c qemu:///system start maquina1 &> /dev/null
echo " "
sleep 50
echo "Memoria RAM actual de la máquina1"
ssh -i id_ecdsa debian@$dirip "free -h"
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"

#Crea un snapshot de la máquina virtual
echo "----- Creando snaptshot de la máquina virtual -----"
echo "Apagando maquina1..."
virsh -c qemu:///system shutdown maquina1 &> /dev/null
sleep 20
read -p "Introduce el nombre que le quieres asignar a la snapshot: " nombresnap
echo "Creando snapshot..."
virsh -c qemu:///system snapshot-create-as maquina1 --name $nombresnap --description "Snapshot creada para el script" --disk-only --atomic &> /dev/null
if [ $? = 0 ]
then
    echo "Snapshot creado a la máquina virtual con el nombre " $nombresnap
else
    echo "Problemas al crear el snapshot a la máquina virtual"
fi
sleep 3
echo "---------------------------------------------------------"
echo -e "\n"
echo "SCRIPT FINALIZADO. Aut: Ángel Suárez Pérez"