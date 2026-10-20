# A day in the life of a VM: the request.
# Rendered by "./dayinlife.sh prep" into life/app1.yaml (adds your SSH public key).
# Lines starting with '#' in column 1 are dropped when rendering.
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: app1
  namespace: dayinlife
  labels: {app: app1, owner: team-payments}
spec:
  runStrategy: Always                # keep it running; restart it if it stops
  preference:                        # OS defaults: virtio, firmware, clock
    {kind: VirtualMachineClusterPreference, name: fedora}
  dataVolumeTemplates:               # its disk: a clone of the Fedora golden image
  - metadata: {name: app1-root}
    spec:
      sourceRef: {kind: DataSource, name: fedora, namespace: openshift-virtualization-os-images}
      storage: {resources: {requests: {storage: 30Gi}}}
  template:
    metadata:
      labels: {app: app1}
    spec:
      domain:
        cpu: {sockets: 1}            # 1 vCPU today
        memory: {guest: 2Gi}         # 2 GiB today
        devices:
          disks:
          - {name: rootdisk, disk: {bus: virtio}}
          - {name: cloudinitdisk, disk: {bus: virtio}}
          interfaces:
          - {name: default, masquerade: {}}
      networks:
      - {name: default, pod: {}}
      volumes:
      - name: rootdisk
        dataVolume: {name: app1-root}
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            hostname: app1
            user: fedora
            password: hc3demo
            chpasswd: {expire: false}
            ssh_authorized_keys:
              - __SSH_PUBKEY__
