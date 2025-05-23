{
  description = "LibVirt domain management";

  inputs =
    {
      nixpkgs =
        {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          ref = "nixos-24.11";
        };
    };

  outputs = { self, nixpkgs }:
    let
      packages = import nixpkgs { system = "x86_64-linux"; };

      nixvirtPythonModulePackage = packages.runCommand "nixvirtPythonModulePackage" { }
        ''
          mkdir  -p $out/lib/python3.11/site-packages/
          ln -s ${tool/nixvirt.py} $out/lib/python3.11/site-packages/nixvirt.py
        '' // { pythonModule = packages.python311; };

      pythonInterpreterPackage = libvirt: packages.python311.withPackages (ps:
        [
          (ps.libvirt.override { inherit libvirt; })
          ps.lxml
          ps.xmldiff
          nixvirtPythonModulePackage
        ]);

      setShebang = name: path: libvirt: packages.runCommand name { }
        ''
          sed -e "1s|.*|\#\!${pythonInterpreterPackage libvirt}/bin/python3|" ${path} > $out
          chmod 755 $out
        '';

      virtdeclareFile = setShebang "virtdeclare" tool/virtdeclare;
      moduleHelperFile = setShebang "nixvirt-module-helper" tool/nixvirt-module-helper;

      mklib = import ./lib.nix;

      modules = import ./modules.nix { inherit moduleHelperFile; };

      stuff = { inherit packages; };
    in
    {
      lib = mklib stuff;

      apps.x86_64-linux.virtdeclare =
        {
          type = "app";
          program = "${virtdeclareFile packages.libvirt}";
        };

      # for debugging
      apps.x86_64-linux.nixvirt-module-helper =
        {
          type = "app";
          program = "${moduleHelperFile packages.libvirt}";
        };

      formatter.x86_64-linux = packages.nixpkgs-fmt;

      packages.x86_64-linux.default = packages.runCommand "NixVirt" { }
        ''
          mkdir -p $out/bin
          ln -s ${virtdeclareFile packages.libvirt} $out/bin/virtdeclare
        '';

      homeModules.default = modules.homeModule;

      nixosModules.default = modules.nixosModule;

      checks.x86_64-linux = import checks/checks.nix stuff mklib;
    };
}
