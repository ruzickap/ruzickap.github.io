---
title: Provision Windows Server 2016 in AWS using Ansible via CloudFormation
author: Petr Ruzicka
date: 2017-02-13
description: Provision Windows Server 2016 in AWS using Ansible via CloudFormation
categories: [Cloud, DevOps, Windows, linux.xvx.cz]
tags: [ec2, ansible, windows]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2017/02/provision-windows-server-2016-in-aws.html)
{: .prompt-info }

For some testing I had to provision Windows Servers 2016 in AWS. I'm using
Ansible for "linux" server provisioning and managing AWS so I tried it for the
Windows server as well.

Because I'm not a Windows user it was quite complicated for me so here is how I
did it. I'm not sure if it's the right one, but maybe those snippets may help
somebody...

Here is the file/directory structure:

```text
.
├── group_vars
│   └── all
├── tasks
│   ├── create_cf_stack.yml
│   └── win.yml
├── templates
│   └── aws_cf_stack.yml.j2
├── run_aws.sh
└── site_aws.yml
```

Here you can find the files:

- `group_vars/all`

{% raw %}

  ```yaml
  ansible_winrm_operation_timeout_sec: 100
  ansible_winrm_read_timeout_sec: 120

  windows_machines_ansible_user: ansible
  windows_machines_ansible_pass: ansible

  domain: example.com
  system_security_settings_tmp_file: c:\\secedit-export.cfg

  ### AWS

  aws_region: us-east-1
  aws_cf_vpc_id: vpc-bxxxxxx6
  aws_cf_subnet_id: subnet-7xxxxxx7
  aws_cf_stack_name: windows-example
  aws_cf_keyname: "{{ ansible_user_id }}"

  aws_cf_tags:
    Application: Windows CloudFormation Stack
    Consumer: petr.ruzicka@gmail.com
    Costcenter: 10000000
    Division: My IT
    Environment: Development

  aws_cf_instance_tags:
    Application: IPA Coudformation
    Consumer: "{{ aws_cf_tags.Consumer }}"
    Costcenter: "{{ aws_cf_tags.Costcenter }}"
    Division: "{{ aws_cf_tags.Division }}"
    Environment: "{{ aws_cf_tags.Environment }}"
  ```

{% endraw %}

- `tasks/create_cf_stack.yml`

{% raw %}

  ```yaml
  - name: Search for the latest Windows Server 2016 AMI
    ec2_ami_find:
      region: "{{ aws_region }}"
      platform: windows
      owner: amazon
      architecture: x86_64
      name: "Windows_Server-2016-English-Full-Base*"
      sort: creationDate
      sort_order: descending
      no_result_action: fail
    changed_when: False
    register: win_server_ami_id

  - name: Create temporary CloudFormation temaplte
    template:
      src: templates/aws_cf_stack.yml.j2
      dest: /tmp/aws_cf_stack.yml
    changed_when: False

  - name: create/update stack
    cloudformation:
      region: "{{ aws_region }}"
      stack_name: "{{ ansible_user_id }}-{{ aws_cf_stack_name }}"
      state: present
      disable_rollback: true
      template: /tmp/aws_cf_stack.yml
      tags: "{{ aws_cf_tags }}"
    register: aws_cf_stack

  - name: Remove temporary CloudFormation temaplte
    file: path=/tmp/aws_cf_stack.yml state=absent
    changed_when: False

  - name: Get facts about the newly created instances
    ec2_remote_facts:
      region: "{{ aws_region }}"
      filters:
        instance-state-name: running
        "tag:aws:cloudformation:stack-name": "{{ ansible_user_id }}-{{ aws_cf_stack_name }}"
    register: ec2_facts

  - name: Get volumes ids
    ec2_vol:
      region: "{{ aws_region }}"
      instance: "{{ item.id }}"
      state: list
    with_items: "{{ ec2_facts.instances }}"
    register: ec2_instances_volumes
    loop_control:
      label: "{{ item.id }} - {{ item.private_ip_address }} - {{ item.tags.Name }}"

  - name: Tag volumes
    ec2_tag:
      region: "{{ aws_region }}"
      resource: "{{ item.1.id }}"
      tags: "{{ aws_cf_instance_tags | combine({ 'Instance': item.1.attachment_set.instance_id }, { 'Device': item.1.attachment_set.device }, { 'Name': item.0.item.tags.Name + ' ' + item.1.attachment_set.device }) }}"
    with_subelements:
      - "{{ ec2_instances_volumes.results }}"
      - volumes
    loop_control:
      label: "{{ item.1.id }} - {{ item.1.attachment_set.device }}"

  - name: Wait for RDP to come up
    wait_for: host={{ item.private_ip_address }} port=3389
    with_items: "{{ ec2_facts.instances }}"
    when: item.tags.Hostname | match ("^win\d{2}")
    loop_control:
      label: "{{ item.private_ip_address }} - {{ item.id }} - {{ item.tags.Name }}"

  - name: Get AWS Windows Administrator password
    ec2_win_password:
      instance_id: "{{ item.id }}"
      region: "{{ aws_region }}"
      key_file: ~/.ssh/id_rsa
      wait: yes
      wait_timeout: 300
    with_items: "{{ ec2_facts.instances }}"
    changed_when: false
    when: item.tags.Hostname | match ("^win\d{2}")
    register: win_ec2_passwords
    loop_control:
      label: "{{ item.id }} - {{ item.private_ip_address }} - {{ item.tags.Name }}"

  - name: Add AWS Windows AD hosts to group winservers
    add_host:
      name: "{{ item.1.tags.Name }}"
      ansible_ssh_host: "{{ item.1.private_ip_address }}"
      ansible_port: 5986
      ansible_user: "{{ windows_machines_ansible_user }}"
      ansible_password: "{{ windows_machines_ansible_pass }}"
      ansible_winrm_server_cert_validation: ignore
      ansible_connection: 'winrm'
      groups: winservers
      site_name: "{{ ansible_user_id }}-{{ aws_cf_stack_name }}"
    changed_when: false
    when: item.0.win_password is defined and item.1.tags.Hostname | match ("^win\d{2}")
    with_together:
      - "{{ win_ec2_passwords.results }}"
      - "{{ ec2_facts.instances }}"
    loop_control:
      label: "{{ item.1.id }} - {{ item.1.private_ip_address }} - {{ item.1.tags.Name }}"
  ```

{% endraw %}

- `tasks/win.yml`

  ```yaml
  ---
  - name: Start NTP service (w32time)
    win_service:
      name: w32time
      state: started

  - name: Configure NTP
    raw: w32tm /config /manualpeerlist:"0.rhel.pool.ntp.org" /reliable:yes /update

  - name: Install Chromium
    win_chocolatey: name=chromium

  - name: Install Double Commander
    win_chocolatey: name=doublecmd

  - name: Add Double Commander link to Desktop
    raw: $WScriptShell = New-Object -ComObject WScript.Shell; $Shortcut = $WScriptShell.CreateShortcut("${Env:Public}\Desktop\Double Commander.lnk"); $Shortcut.TargetPath = "${Env:ProgramFiles}\Double Commander\doublecmd.exe"; $Shortcut.Save()

  - name: Install Putty
    win_chocolatey: name=putty.install

  - name: Add PuTTY link to Desktop
    raw: $WScriptShell = New-Object -ComObject WScript.Shell; $Shortcut = $WScriptShell.CreateShortcut("${Env:Public}\Desktop\PuTTY.lnk"); $Shortcut.TargetPath = "${Env:ProgramFiles(x86)}\PuTTY\putty.exe"; $Shortcut.Save()
  ```

- `templates/aws_cf_stack.yml.j2`

{% raw %}

  ```yaml
  ---
  AWSTemplateFormatVersion: "2010-09-09"

  Description:
    Windows 2016 Template

  Resources:
    alltraffic:
      Type: AWS::EC2::SecurityGroup
      Properties:
        GroupDescription: SG Permitting All Traffic
        VpcId: {{ aws_cf_vpc_id }}
        SecurityGroupIngress:
          CidrIp: 0.0.0.0/0
          IpProtocol: -1
          FromPort: -1
          ToPort: -1
        SecurityGroupEgress:
          CidrIp: 0.0.0.0/0
          IpProtocol: -1
          FromPort: -1
          ToPort: -1
        Tags:
          - Key: Name
            Value: "All Traffic SG"
          - Key: Costcenter
            Value: {{ aws_cf_tags.Costcenter }}

    win01:
      Type: AWS::EC2::Instance
      Metadata:
        AWS::CloudFormation::Init:
          config:
            files:
              c:\cfn\cfn-hup.conf:
                content: !Sub |
                  [main]
                  stack=${AWS::StackId}
                  region=${AWS::Region}
              c:\cfn\hooks.d\cfn-auto-reloader.conf:
                content: !Sub |
                  [cfn-auto-reloader-hook]
                  triggers=post.update
                  path=Resources.win01.Metadata.AWS::CloudFormation::Init
                  action=cfn-init.exe -v -s ${AWS::StackId} -r win01 --region ${AWS::Region}
              c:\cfn\hooks.d\enable_winrm.ps1:
                content: !Sub |
                  #Enable WinRM
                  Invoke-Expression ((New-Object System.Net.Webclient).DownloadString('https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1'))

                  #Disable password complexity
                  secedit /export /cfg {{ system_security_settings_tmp_file }}
                  (gc {{ system_security_settings_tmp_file }}).replace("PasswordComplexity = 1", "PasswordComplexity = 0") | Out-File {{ system_security_settings_tmp_file }}
                  secedit /configure /db c:\windows\security\local.sdb /cfg {{ system_security_settings_tmp_file }} /areas SECURITYPOLICY
                  rm -force {{ system_security_settings_tmp_file }} -confirm:$false

                  #Add user ansible and add it to group 'WinRMRemoteWMIUsers__'+'Administrators' to enable WinRM
                  $Computer = [ADSI]"WinNT://$Env:COMPUTERNAME"
                  $User = $Computer.Create("User", "{{ windows_machines_ansible_user }}")
                  $User.SetPassword("{{ windows_machines_ansible_pass }}")
                  $User.SetInfo()
                  $User.FullName = "Ansible WinRM user"
                  $User.SetInfo()
                  $User.UserFlags = 65536 # Password never Expires
                  $User.SetInfo()
                  $Group = $Computer.Children.Find('Administrators')
                  $Group.Add(("WinNT://$Env:COMPUTERNAME/{{ windows_machines_ansible_user }}"))
                  $Group = $Computer.Children.Find('WinRMRemoteWMIUsers__')
                  $Group.Add(("WinNT://$Env:COMPUTERNAME/{{ windows_machines_ansible_user }}"))
            commands:
              enable_winrm:
                command: powershell.exe -ExecutionPolicy Bypass -NoLogo -NonInteractive -NoProfile -File c:\cfn\hooks.d\enable_winrm.ps1 -SkipNetworkProfileCheck -CertValidityDays 3650
            services:
              windows:
                cfn-hup:
                  enabled: true
                  ensureRunning: true
                  files:
                    - c:\cfn\cfn-hup.conf
                    - c:\cfn\hooks.d\cfn-auto-reloader.conf
      Properties:
        InstanceType: t2.medium
        ImageId: {{ (win_server_ami_id.results | first).ami_id }}
        KeyName: {{ aws_cf_keyname }}
        SecurityGroupIds: [ !Ref alltraffic ]
        SubnetId: {{ aws_cf_subnet_id }}
        UserData:
          "Fn::Base64":
            !Sub |
              <script>
              cfn-init.exe -v -s ${AWS::StackId} -r win01 --region ${AWS::Region}
              </script>
        Tags:
          - Key: Name
            Value: win01.{{ domain }}
          - Key: Hostname
            Value: win01.{{ domain }}
          - Key: Role
            Value: Windows Server 2016
  {% for (key, value) in aws_cf_instance_tags.items() %}
          - Key: {{ key }}
            Value: {{ value }}
  {% endfor %}

  Outputs:
    winservers:
      Value: !Join [ ' ', [ win01, !GetAtt win01.PrivateIp ] ]
      Description: Windows Servers
  ```

{% endraw %}

- `site_aws.yml`

  ```yaml
  ---
  - name: Provision Stack
    hosts: localhost
    connection: local

    tasks:
      - include: tasks/create_cf_stack.yml

  - name: Common tasks for windows machines
    hosts: winservers
    any_errors_fatal: true

    tasks:
      - include: tasks/win.yml
  ```

- `run_aws.sh`

  ```bash
  ansible-playbook -i "127.0.0.1," site_aws.yml
  ```

You needs to run the `run_aws.sh` and do necessary modifications in the
`group_vars/all` to get it working...

Enjoy :-)
