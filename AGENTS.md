# NixOS en un Samsung Galaxy Book4 Edge (NP964XMA, 16")

Laptop ARM64 con SoC Qualcomm Snapdragon X Elite (X1E80100). Casi nada
funciona con un NixOS de fabrica: hace falta kernel propio, firmware
extraido de la particion de Windows, DTB propio y un driver de bateria
escrito a mano. Este repo es todo eso.

El sistema arranca por device tree, no por ACPI. Eso importa mucho mas de
lo que parece y explica varias de las cosas rotas (ver "Callejones
cerrados").

## Comandos

```sh
sudo nixos-rebuild switch --flake ~/nixos#nix-book   # sistema
sudo nixos-rebuild boot   --flake ~/nixos#nix-book   # sistema, aplica al reiniciar
home-manager switch --flake ~/nixos#matias           # usuario
```

Cualquier cambio al config del kernel recompila el kernel entero: entre 30
y 60 minutos en esta maquina. Conviene juntar cambios y hacer un solo
rebuild.

## Estructura

```
flake.nix                              nixosConfigurations.nix-book, homeConfigurations.matias
nix/system/x1e.nix                     TODO lo especifico de este hardware
nix/system/default.nix                 el resto del sistema
nix/system/hardware.nix                particiones
nix/system/samsung-galaxybook-battery.c driver de bateria (vendorizado)
nix/system/book4edge-touchpad-0x50.patch parche al dts
kernel-binary/kernel.config            config base del kernel
kernel-binary/book4edge16.dtb          DTB viejo, solo como escape de arranque
firmware/                              firmware, parte irreemplazable
nix/home/                              home-manager
```

Preferencia del usuario: **pocos archivos consolidados, no muchos chicos
esparcidos.** Todo lo del hardware va a `x1e.nix` aunque quede largo.

## Reglas duras

Estas no son estilo, son cosas que rompen la maquina o pierden datos.

1. **Nunca parar ni reiniciar el ADSP en caliente.** Un
   `echo stop > /sys/class/remoteproc/remoteproc0/state` colgo la maquina
   entera y dejo el arranque siguiente inestable. El peligro no era el
   firmware ajeno que se estaba probando (TrustZone lo rechazo limpio, -22);
   el peligro es tocar el ADSP en runtime. No hay motivo para hacerlo.

2. **No borrar `kernel-binary/book4edge16.dtb`.** Parece redundante porque
   el DTB se genera en cada compilacion, pero es la unica salida si un DTB
   generado no bootea. Ver "El DTB".

3. **No borrar ni "limpiar" `firmware/qcom/x1e80100/SAMSUNG/`.** No esta en
   linux-firmware ni en ningun repo publico. Salio de la particion de
   Windows de esta maquina. Si se pierde, se pierde el ADSP y con el la
   pantalla y el audio. El resto de `firmware/` si es reemplazable desde
   upstream, pero se versiona igual para que una reinstalacion no dependa
   de la red.

4. **No correr `nix-collect-garbage -d` con un kernel nuevo sin probar.**
   Destruye las generaciones viejas, que son el unico rollback. `nix store gc`
   (sin `-d`) es seguro: libera espacio y conserva las generaciones.

5. **El DTB es compartido entre todas las generaciones.** `extraPerEntryConfig`
   es un string unico que GRUB aplica a cada entrada, incluidas las viejas.
   Un DTB roto no se arregla eligiendo una generacion anterior. Es el unico
   punto del sistema que el rollback no cubre.

## El kernel

Se compila desde el arbol de **zensanp/linux-book4-edge** (branch
`x1e80100-book4e-6.19-14-tmp`), pinneado por rev y hash en `x1e.nix`. No se
usa el binario que venia del Ubuntu hackeado: el kernel es 100%
reproducible desde la fuente.

`CONFIG_LOCALVERSION_AUTO` se apaga a proposito. Ese flag hace que
`scripts/setlocalversion` lea el `.git` del arbol y agregue `-g<sha>-dirty`
al `modDirVersion`, que sin `.git` no es reproducible y ademas deja de
coincidir con lo que NixOS espera.

### Agregar opciones al kernel

El `.config` base (`kernel-binary/kernel.config`) sale del kernel de Ubuntu
para X1E y **no se edita**. Las opciones se agregan declarativamente en las
listas `tristate` (`=m`) y `boolean` (`=y`) dentro del `runCommand` de
`x1e.nix`. Asi el `git diff` muestra la intencion y no un blob de 300 KB.

Antes de agregar una opcion, **verificar su tipo real** en el Kconfig del
arbol: poner `=y` en algo que es `tristate` (o al reves) hace que
`make oldconfig` la descarte en silencio y el modulo no aparece.

```sh
grep -rA5 "^config NOMBRE_SIN_CONFIG_$" $SRC/net $SRC/drivers
```

Despues del rebuild, confirmar que la opcion realmente entro:

```sh
grep -E '^CONFIG_(FOO|BAR)=' /nix/store/*-linux-6.19.14-dev/lib/modules/6.19.14/build/.config
```

### Parches al kernel

Van por `kernelPatches` en `x1e.nix`. Hoy hay uno solo, el del touchpad.
Es el mismo mecanismo por el que entrarian los parches de pinctrl del audio.

### Subir de version

Cambiar `rev` y `hash` del `fetchFromGitHub`, y `version`/`modDirVersion` si
cambia. Ojo: la branch se llama `6.19-14`, que es la **6.19.14**, no la
version de 14 pulgadas. Ese malentendido ya costo un build fallido.

## El DTB

Sale del mismo build que el kernel:
`${book4eKernel}/dtbs/qcom/x1e80100-samsung-galaxy-book4-edge.dtb`.

El dts del arbol describe otro SKU: pone el touchpad en
**0x40**, con `hid-descr-addr` 0x0e y sin reguladores. En el NP964XMA el
touchpad esta en **0x50**, con `hid-descr-addr` 0xd1 y necesita
`vdd-supply` y `vddl-supply` explicitos. De ahi el parche. Sin el, la
laptop bootea sin touchpad.

Fuera de ese nodo, el DTB generado y el blob viejo son identicos; la unica
otra diferencia es `__symbols__`, metadata de overlays que explica los
~50 KB de mas. Eso tambien sirve para saber cual esta cargado:

```sh
ls -d /sys/firmware/devicetree/base/__symbols__   # existe => el generado
```

Los DTBs se instalan con `extraPrepareConfig`, no con `extraFiles`, porque
`extraFiles` copia al ESP (`/boot/efi`) y GRUB busca el devicetree en
`@bootRoot@` (= `/boot`, que en esta maquina vive en sda7 junto con `/`).

Si un DTB generado no bootea: en GRUB apretar `e`, cambiar la linea
`devicetree` a `book4edge16.dtb`, Ctrl-X.

## Bateria

El camino Qualcomm (`qcom-battmgr` sobre `pmic_glink`) esta muerto en esta
maquina. El driver `samsung-galaxybook-battery.c` habla directo al EC
**ENE KB9058** por I2C, en el bus 2 direccion 0x64. Viene de SaddyTech, con
un arreglo local: en el SKU de 16" el EC reporta la corriente como magnitud
sin signo, asi que la direccion se toma de `B1ST` (que si es confiable) y
del valor crudo se usa solo el modulo. Sin eso, una bateria descargandose
se reporta como cargando.

El EC no tiene nodo en el DTB, asi que se instancia por sysfs desde un
servicio systemd (`samsung-galaxybook-battery`) escribiendo en
`/sys/bus/i2c/devices/i2c-2/new_device`.

## Estado del hardware

| | estado |
|---|---|
| bateria | anda (driver propio contra el EC) |
| GPU | acelerada, Adreno X1-85, Mesa + turnip |
| touchpad | anda, con el dts parcheado a 0x50 |
| teclado, wifi, bluetooth | andan |
| suspend | anda; al volver a X la pantalla queda azul hasta cambiar de VT y volver (falta el modeset del DPU). Cosmetico, no probado desde niri |
| USB-C datos | anda |
| **USB-C PD / altmode** | **sin arreglo posible, ver abajo** |
| audio | roto: los `wsa884x` (amplificadores) no bindean |
| camara | sin soporte |

## Callejones cerrados

**USB-C PD y altmode: no tiene arreglo.** No proponer soluciones para esto.
Todo lo siguiente ya se probo:

- `pmic_glink` no levanta porque el ADSP de Samsung **no trae el charger PD**.
  `pg->ept` queda NULL y todo devuelve `-EAGAIN`.
- Se probo `qcom_pd_mapper` en kernel y `pd-mapper` en userspace con los
  `.jsn` correctos. No cambia nada: el problema no es el mapeo de dominios,
  es que el codigo no esta en la imagen.
- Se probaron imagenes de ADSP de otros fabricantes. **TrustZone las rechaza**
  contra el `OEM_PK_HASH` fusionado en el SoC (`-22` en
  `qcom_scm_pas_init_image`). No hay forma de saltearlo.
- Windows lo resuelve con drivers ACPI propios de Samsung (EmuEC, UcmEm) que
  Linux no tiene. Y Linux arranca por device tree, sin ACPI, asi que ni
  siquiera es cuestion de portarlos.

Consecuencia practica: la laptop **no carga por USB-C con el sistema
encendido**. Hay que apagarla para enchufarla.

## Repos de referencia

- **zensanp/linux-book4-edge** — de aca sale el kernel. Es la fuente real.
- **SaddyTech** — de aca salio el driver de bateria, y de aca saldrian los
  parches de pinctrl del audio. **Su README no es confiable:** lista la GPU
  como rota cuando aca anda acelerada, y lo que llama "USB-C funcionando"
  son datos, no PD ni altmode. Leerlo con eso en mente.

## Pendientes

- Reinstalar en una particion mas grande (plan principal del usuario).
- Audio: parches de pinctrl para que bindeen los `wsa884x`.
- Suspend: la pantalla azul al volver a X se arregla con un VT switch. Vale
  probar desde niri para saber si es del DPU o de X11.
- `DEBUG_INFO_BTF` para poder usar BPF con CO-RE. Obliga a apagar
  `DEBUG_INFO_REDUCED` y lleva el build de ~12 GB a ~30 GB. Diferido a
  proposito hasta tener disco.
- Camara.

## Historia del repo

El repo se reinicio (`git init` nuevo) para sacar de la historia el kernel
binario y sus modulos, ~420 MB que ya no hacen falta. La historia vieja
quedo en `~/nixos-viejo.bundle`, fuera del repo.
