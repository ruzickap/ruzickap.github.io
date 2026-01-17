---
title: Use Ansible to create and tag Instances in AWS (EC2)
author: Petr Ruzicka
date: 2017-02-16
description: Use Ansible to create and tag Instances in AWS (EC2)
categories: [AWS, Linux]
tags: [ec2, tag]
---

> Original post from [linux.xvx.cz](https://linux.xvx.cz/2017/02/use-ansible-to-create-and-tag-instances.html)
{: .prompt-info }

It may be handy to quickly create a few instances for testing in AWS.

For such a case I'm using a simple Ansible playbook which can deploy a few
CentOS 7
instances, configure disks, tags volumes and instances and install public ssh
key to root for example.

![image](/assets/img/posts/2017/2017-02-16-use-ansible-to-create-and-tag-instances-in-aws-ec2/Screenshot_20170216_154501.avif)
AWS Console

Here is the playbook:

{% raw %}

```yaml
---
- name: Create Instance in AWS
  hosts: localhost
  connection: local
  gather_facts: false

  vars:
    aws_access_key: "xxxxxx"
    aws_secret_key: "xxxxxx"
    security_token: "xxxxxx"
    aws_instance_type: "t2.nano"
    aws_region: "us-east-1"
    aws_security_group: "All Ports"
    aws_ami_owner: "099720109477"
    aws_key_name: "ruzickap"
    aws_instance_initiated_shutdown_behavior: "terminate"
    aws_instances_count: 3
    site_name: "ruzickap-test"
    aws_tags:
      Name: "{{ site_name }}"
      Application: "{{ site_name }}"
      Environment: "Development"
      Costcenter: "1xxxxxxx3"
      Division: "My"
      Consumer: "petr.ruzicka@gmail.com"

  tasks:
    - name: Search for the latest CentOS AMI
      shell: aws ec2 describe-images --region {{ aws_region }} --owners aws-marketplace --output text --filters "Name=product-code,Values=aw0evgkw8e5c1q413zgy5pjce" "Name=virtualization-type,Values=hvm" --query 'sort_by(Images, &CreationDate)[-1].[ImageId]' --output 'text'
      changed_when: False
      register: centos_ami_id

    - name: Get Private Subnets in VPC
      ec2_vpc_subnet_facts:
        aws_access_key: "{{ ec2_access_key }}"
        aws_secret_key: "{{ ec2_secret_key }}"
        security_token: "{{ access_token }}"
        region: "{{ aws_region }}"
        filters:
          "tag:Type": Private
      register: ec2_vpc_subnet_facts

    - debug: "msg='name: {{ ec2_vpc_subnet_facts.subnets[0].tags.Name }} | subnet_id: {{ ec2_vpc_subnet_facts.subnets[0].id }} | cidr_block: {{ ec2_vpc_subnet_facts.subnets[0].cidr_block }} | region: {{ aws_region }}'"

    - name: Create an EC2 instance
      ec2:
        aws_access_key: "{{ ec2_access_key }}"
        aws_secret_key: "{{ ec2_secret_key }}"
        security_token: "{{ access_token }}"
        region: "{{ aws_region }}"
        key_name: "{{ aws_key_name }}"
        instance_type: "{{ aws_instance_type }}"
        image: "{{ centos_ami_id.stdout }}"
        instance_tags: "{{ aws_tags }}"
        user_data: |
          #!/bin/bash
          echo "Defaults:centos !requiretty" > /etc/sudoers.d/disable_requiretty
          yum upgrade -y yum
        wait: yes
        exact_count: "{{ aws_instances_count }}"
        count_tag:
          Application: "{{ aws_tags.Application }}"
        group: "{{ aws_security_group }}"
        vpc_subnet_id: "{{ ec2_vpc_subnet_facts.subnets[0].id }}"
        instance_initiated_shutdown_behavior: "{{ aws_instance_initiated_shutdown_behavior }}"
        volumes:
          - device_name: /dev/sda1
            volume_type: gp2
            volume_size: 9
            delete_on_termination: true
          - device_name: /dev/sdb
            volume_type: standard
            volume_size: 1
            delete_on_termination: true
      register: ec2_instances

    - block:
      - name: Set name tag for AWS instances
        ec2_tag:
          aws_access_key: "{{ ec2_access_key }}"
          aws_secret_key: "{{ ec2_secret_key }}"
          security_token: "{{ access_token }}"
          region: "{{ aws_region }}"
          resource: "{{ item.1.id }}"
          tags:
            Name: "{{ aws_tags.Name }}-{{ '%02d' | format(item.0 + 1) }}"
        with_indexed_items: "{{ ec2_instances.instances }}"
        loop_control:
          label: "{{ item.1.id }} - {{ aws_tags.Name }}-{{ '%02d' | format(item.0 + 1) }}"

      - name: Get volumes ids
        ec2_vol:
          aws_access_key: "{{ ec2_access_key }}"
          aws_secret_key: "{{ ec2_secret_key }}"
          security_token: "{{ access_token }}"
          region: "{{ aws_region }}"
          instance: "{{ item }}"
          state: list
        with_items: "{{ ec2_instances.instance_ids }}"
        register: ec2_instances_volumes
        loop_control:
          label: "{{ item }}"

      - name: Tag volumes
        ec2_tag:
          aws_access_key: "{{ ec2_access_key }}"
          aws_secret_key: "{{ ec2_secret_key }}"
          security_token: "{{ access_token }}"
          region: "{{ aws_region }}"
          resource: "{{ item.1.id }}"
          tags: "{{ aws_tags | combine({'Instance': item.1.attachment_set.instance_id}, {'Device': item.1.attachment_set.device}) }}"
        with_subelements:
          - "{{ ec2_instances_volumes.results }}"
          - volumes
        loop_control:
          label: "{{ item.1.id }} - {{ item.1.attachment_set.device }}"

      - name: Wait for SSH to come up
        wait_for: host={{ item.private_ip }} port=22 delay=60 timeout=320 state=started
        with_items: '{{ ec2_instances.instances }}'
        loop_control:
          label: "{{ item.id }} - {{ item.private_ip }}"

      when: ec2_instances.changed

    - name: Gather EC2 facts
      ec2_remote_facts:
        aws_access_key: "{{ ec2_access_key }}"
        aws_secret_key: "{{ ec2_secret_key }}"
        security_token: "{{ access_token }}"
        region: "{{ aws_region }}"
        filters:
          instance-state-name: running
          "tag:Application": "{{ site_name }}"
      register: ec2_facts

    - name: Add AWS hosts to groups
      add_host:
        name: "{{ item.tags.Name }}"
        ansible_ssh_host: "{{ item.private_ip_address }}"
        groups: ec2_hosts
        site_name: "{{ site_name }}"
      changed_when: false
      with_items: "{{ ec2_facts.instances }}"
      loop_control:
        label: "{{ item.id }} - {{ item.private_ip_address }} - {{ item.tags.Name }}"


- name: Install newly created machines
  hosts: ec2_hosts
  any_errors_fatal: true
  remote_user: centos
  become: yes

  tasks:
    - name: Set hostname
      hostname: name={{ inventory_hostname }}

    - name: Build hosts file
      lineinfile: dest=/etc/hosts regexp='{{ item }}' line="{{ hostvars[item].ansible_default_ipv4.address }} {{ item }}"
      when: hostvars[item].ansible_default_ipv4.address is defined
      with_items: "{{ groups['ec2_hosts'] }}"

    - name: Add SSH key to root
      authorized_key: user=root key="{{ lookup('file', item) }}"
      with_items:
        - ~/.ssh/id_rsa.pub
      tags:
        - ssh_keys
```

{% endraw %}

You can easily run it using:

ansible-playbook -i "127.0.0.1," site_aws.yml

I hope some parts will be handy...

Enjoy :-)
