{ config, pkgs, lib, ... }:
let
  book4eKernel = pkgs.linuxManualConfig {
    version = "6.19.14";
    modDirVersion = "6.19.14";
    src = pkgs.fetchFromGitHub {
      owner = "zensanp";
      repo = "linux-book4-edge";
      rev = "3fd918e7b73e36a02a50f2312c9f252366f69774";
      hash = "sha256-69DcsZn/0wfFN1hYYydyJbsPIDgbdpr43PyifxltClU=";
    };
    # La config del binario actual, pero sin LOCALVERSION_AUTO: ese flag hace
    # que setlocalversion lea el .git del arbol de compilacion y agregue
    # "-g<sha>-dirty". Sin .git no es reproducible y el modDirVersion no
    # coincidiria con el que NixOS espera.
    configfile =
      let
        # La config de Ubuntu X1E no trae varias cosas que cualquier kernel de
        # distro si. Verificadas una por una contra el Kconfig de este arbol.
        tristate = [
          # contenedores / podman: sin estas netavark no arma la red
          "IPVLAN" "VXLAN" "DUMMY"
          "NETFILTER_XT_MATCH_COMMENT" "NETFILTER_XT_MATCH_MULTIPORT"
          "NETFILTER_XT_TARGET_MASQUERADE" "NETFILTER_XT_NAT"
          "IP_NF_FILTER" "IP_NF_NAT" "IP_NF_MANGLE" "IP6_NF_NAT"
          "NFT_LOG" "NFT_LIMIT"
          # NFT_COMPAT es el que faltaba: iptables aca es iptables-nft, y sin
          # esto no puede usar targets de x_tables (MASQUERADE) sobre nf_tables.
          "NFT_COMPAT" "NFT_REDIR" "NFT_CONNLIMIT"
          "NFT_FIB_IPV4" "NFT_FIB_IPV6" "NFT_FIB_INET"
          "NFT_NUMGEN" "NFT_QUOTA" "NFT_HASH" "NFT_SOCKET" "NFT_TPROXY"
          "NF_TABLES_BRIDGE" "NF_CONNTRACK_BRIDGE"
          # helpers de conntrack que trae cualquier distro
          "NF_CONNTRACK_FTP" "NF_CONNTRACK_IRC" "NF_CONNTRACK_SIP"
          "NF_CONNTRACK_TFTP"
          # red
          "WIREGUARD" "TLS" "VHOST_NET"
          # filesystems: montar ISOs, discos ajenos, compartidos SMB
          "XFS_FS" "F2FS_FS" "CIFS" "ISO9660_FS" "UDF_FS"
          # storage
          "DM_CRYPT" "DM_SNAPSHOT" "ZRAM"
          # entrada virtual (ydotool, autotype, Wayland)
          "INPUT_UINPUT"
        ];
        boolean = [
          "ZSWAP" "FS_ENCRYPTION" "HIDRAW" "USB_HIDDEV"
          # netfilter: conntrack completo y las familias que faltaban
          "NF_TABLES_NETDEV" "NF_TABLES_ARP"
          "NF_CONNTRACK_MARK" "NF_CONNTRACK_ZONES" "NF_CONNTRACK_PROCFS"
          "NF_CONNTRACK_TIMEOUT" "NF_CONNTRACK_TIMESTAMP" "NF_CONNTRACK_LABELS"
          # tracing: alcanza para perf y kprobes. BPF con CO-RE necesitaria
          # ademas DEBUG_INFO_BTF, que obliga a apagar DEBUG_INFO_REDUCED y
          # lleva el build de ~12 GB a ~30 GB. Pendiente.
          "KPROBES" "FTRACE" "FUNCTION_TRACER"
        ];
      in
      pkgs.runCommand "book4edge-kernel.config" { } ''
        sed 's/^CONFIG_LOCALVERSION_AUTO=y$/# CONFIG_LOCALVERSION_AUTO is not set/' \
          ${../../kernel-binary/kernel.config} > $out
        chmod +w $out
        set_opt() {
          if grep -q "^# CONFIG_$1 is not set$" $out; then
            sed -i "s/^# CONFIG_$1 is not set$/CONFIG_$1=$2/" $out
          elif ! grep -q "^CONFIG_$1=" $out; then
            echo "CONFIG_$1=$2" >> $out
          fi
        }
        for o in ${lib.concatStringsSep " " tristate}; do set_opt $o m; done
        for o in ${lib.concatStringsSep " " boolean};  do set_opt $o y; done
      '';
    # El dts del arbol describe otro SKU: el touchpad va a 0x50, no 0x40.
    kernelPatches = [{
      name = "book4edge-touchpad-0x50";
      patch = ./book4edge-touchpad-0x50.patch;
    }];
    allowImportFromDerivation = true;
  };

  # Driver de bateria: habla directo al EC ENE KB9058 por I2C. La via Qualcomm
  # (qcom-battmgr) esta muerta porque el ADSP de Samsung no trae el charger PD.
  samsung-galaxybook-battery = pkgs.stdenv.mkDerivation {
    pname = "samsung-galaxybook-battery";
    version = "1.0.0";
    src = ./samsung-galaxybook-battery.c;
    nativeBuildInputs = book4eKernel.moduleBuildDependencies;
    dontUnpack = true;
    buildPhase = ''
      mkdir -p m && cd m
      cp $src samsung_galaxybook_battery.c
      echo 'obj-m := samsung_galaxybook_battery.o' > Makefile
      make -C ${book4eKernel.dev}/lib/modules/${book4eKernel.modDirVersion}/build \
        M=$PWD modules
    '';
    installPhase = ''
      install -Dm444 samsung_galaxybook_battery.ko \
        $out/lib/modules/${book4eKernel.modDirVersion}/extra/samsung_galaxybook_battery.ko
    '';
    meta.description = "Bateria del Samsung Galaxy Book4 Edge via el EC";
  };
in
{
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    configurationLimit = 5;
    # extraFiles copia al ESP (/boot/efi), no a /boot, pero GRUB busca el
    # devicetree en @bootRoot@ (= /boot, en sda7). Por eso los DTBs se
    # instalan aca a mano. El blob que venia del Ubuntu queda como escape:
    # si el generado no bootea, en GRUB se aprieta "e" y se apunta la linea
    # devicetree a book4edge16.dtb.
    extraPrepareConfig = ''
      ${pkgs.coreutils}/bin/install -Dm444 \
        ${book4eKernel}/dtbs/qcom/x1e80100-samsung-galaxy-book4-edge.dtb \
        @bootPath@/book4edge.dtb
      ${pkgs.coreutils}/bin/install -Dm444 \
        ${../../kernel-binary/book4edge16.dtb} @bootPath@/book4edge16.dtb
    '';
    extraPerEntryConfig = "devicetree @bootRoot@/book4edge.dtb";
    gfxmodeEfi = "1200x800";
  };
  boot.loader.efi = {
    canTouchEfiVariables = true;
    efiSysMountPoint = "/boot/efi";
  };
  boot.kernelParams = [
    "pd_ignore_unused" "clk_ignore_unused" "arm64.nopauth"
    "efi=noruntime" "cma=128M"
  ];
  boot.consoleLogLevel = 3;
  # Kernel compilado desde el arbol exacto del que salio el binario que
  # veniamos usando: zensanp/linux-book4-edge, branch x1e80100-book4e-6.19-14-tmp
  # (el "-14-" es 6.19.14, no el SKU de 14 pulgadas).
  #
  # Nuestro binario decia 6.19.14-ge2c46c019aa0-dirty; e2c46c019 es el commit
  # "Ubuntu: update changelog to 6.19.14-jg-4" de esta branch. Los 4 commits que
  # vienen encima (crash fix de jglathe, dts del Book4e, defconfig) son con toda
  # probabilidad lo que estaba sin commitear y causaba el -dirty. Compilando el
  # HEAD obtenemos lo mismo, pero reproducible y con headers.
  boot.kernelPackages = pkgs.linuxPackagesFor book4eKernel;

  boot.extraModulePackages = [ samsung-galaxybook-battery ];
  boot.kernelModules = [ "samsung_galaxybook_battery" ];

  # El driver se ata por i2c_device_id, y sin nodo en el DTB hay que
  # instanciarlo a mano. i2c-2 @ 0x64 verificado en este equipo.
  systemd.services.samsung-galaxybook-battery = {
    description = "Instancia el EC de bateria del Book4 Edge en i2c-2 0x64";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/sh -c 'echo sgbook-battery 0x64 > /sys/bus/i2c/devices/i2c-2/new_device'";
      ExecStop = "${pkgs.bash}/bin/sh -c 'echo 0x64 > /sys/bus/i2c/devices/i2c-2/delete_device'";
    };
  };

  boot.initrd.includeDefaultModules = false;
  boot.initrd.availableKernelModules = lib.mkForce [ "ufs_qcom" "phy_qcom_qmp_ufs" ];
  boot.initrd.systemd.tpm2.enable = false;
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    (pkgs.runCommand "x1e-firmware" { } ''
      mkdir -p $out/lib/firmware
      cp -r ${../../firmware}/* $out/lib/firmware/
    '')
  ];
  services.udev.extraHwdb = ''
    evdev:input:b0018v0CF2p9050*
     ID_INPUT_KEYBOARD_INTEGRATION=internal
  '';

  services.udev.extraRules = ''
    SUBSYSTEM=="input", ENV{ID_INPUT_KEYBOARD}=="1", ENV{ID_INPUT_TABLET_PAD}=="1", ENV{ID_INPUT_TABLET}="", ENV{ID_INPUT_TABLET_PAD}=""
    ACTION=="add|change", SUBSYSTEM=="input", ATTR{name}=="hid-over-i2c 4D49:4150 Touchpad", RUN+="${pkgs.coreutils}/bin/chgrp input $sys$devpath/inhibited", RUN+="${pkgs.coreutils}/bin/chmod g+w $sys$devpath/inhibited"
  '';
  
}
