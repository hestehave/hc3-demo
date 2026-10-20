apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: __NAME__
  namespace: vmlab
  labels:
    app: shop
    tier: __TIER__
spec:
  runStrategy: Always
  instancetype:
    kind: VirtualMachineClusterInstancetype
    name: u1.small
  preference:
    kind: VirtualMachineClusterPreference
    name: fedora
  dataVolumeTemplates:
  - metadata:
      name: __NAME__-root
    spec:
      sourceRef:
        kind: DataSource
        name: fedora
        namespace: openshift-virtualization-os-images
      storage:
        resources:
          requests:
            storage: 30Gi
  template:
    metadata:
      labels:
        app: shop
        tier: __TIER__
    spec:
      domain:
        devices:
          disks:
          - name: rootdisk
            disk: {bus: virtio}
          - name: cloudinitdisk
            disk: {bus: virtio}
          interfaces:
          - name: default
            masquerade: {}
      networks:
      - name: default
        pod: {}
__PROBES__
__AFFINITY__
      volumes:
      - name: rootdisk
        dataVolume:
          name: __NAME__-root
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: fedora
            password: hc3demo
            chpasswd: {expire: false}
            ssh_authorized_keys:
              - __SSH_PUBKEY__
            write_files:
            - path: /srv/www/index.html
              content: |
                __NAME__ · VM
            - path: /etc/systemd/system/webdemo.service
              content: |
                [Unit]
                Description=HC3 demo listener
                After=network-online.target
                [Service]
                ExecStart=/usr/bin/python3 -m http.server __PORT__ --directory /srv/www
                [Install]
                WantedBy=multi-user.target
            runcmd:
            - [systemctl, daemon-reload]
            - [systemctl, enable, --now, webdemo.service]
