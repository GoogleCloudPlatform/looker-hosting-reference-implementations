# VM Operations Runbook

While VM-based instances are not preferred for production workloads you may still need to perform some standard operational procedures on your Looker instance. Let's cover some of the most common activities, including restarting a node, scaling out a clustered instance, and upgrading Looker to a new version.

## Manually Check and Manage Nodes

Sometimes a Looker node may not spin up correctly the first time, or it may crash due to some fluke. For these cases you’ll need to know how to manually check and restart a Looker node.
1. Navigate to **Compute Engine -> VM Instances**.
2. Next to the relevant VM select SSH to open a shell and connect to your VM. (If it is greyed out you may need to click into the VM details first)
> Note: There are [alternate SSH methods](https://cloud.google.com/compute/docs/instances/connecting-to-instance#connect_to_vms) available if you would prefer a different approach.

3. Looker has been set up to run with `systemd`, a standard Linux daemon management tool. We’ll be using `systemctl` commands to interact with the Looker daemon. To check the status of the Looker node, run

```
$ sudo systemctl status looker
```

If the node is active, you should see a response that looks something like:

```
● looker.service - Looker Application
  Loaded: loaded (/etc/systemd/system/looker.service; enabled; vendor preset: enabled)
  Active: active (running) since Tue 2021-05-04 15:18:40 UTC; 7min ago
Main PID: 4068 (java)
   Tasks: 136 (limit: 4915)
  CGroup: /system.slice/looker.service
          └─4068 java -Dcom.sun.akuma.Daemon=daemonized
```

If the node has stopped working for some reason, your status command may look like this instead:

```
● looker.service - Looker Application
  Loaded: loaded (/etc/systemd/system/looker.service; enabled; vendor preset: enabled)
  Active: inactive (dead) since Tue 2021-05-04 15:29:53 UTC; 5m ago
Main PID: 4068 (code=exited, status=1/FAILURE)
```

In this case, you should dig into logs and begin debugging.

If it looks like Looker just didn’t start or crashed for some intermittent reason then you can trigger a restart with:

```
$ sudo systemctl restart looker
```

Recheck  Looker’s status after a minute or two. If you’re still seeing crashes then it’s time to dig deeper into the logs.

## Scale Out A Cluster

The Looker cluster currently has 1 node. Since the instance is clusterable, you can add another node:
1. Navigate back to your `terraform.tfvars` file and locate the `node_count` parameter.
2. Update this value from “1” to “2”
3. Save your changes, then back in the command line execute another round of `terraform plan`  and `terraform apply`
4. Wait for the apply to finish (this should be a very quick change.)

In the GCP console, navigate to **Compute Engine -> Instance Groups** and select your Instance Group. In a moment or two you should see a second VM begin to spin up.

One way to see if your new node is ready is to check the Load Balancing page in GCP. Navigate to **Network Services -> Load Balancing** and select the appropriate load balancer. After a couple of minutes, under "Backend services" you should see 2/2 Healthy - that means your new node has passed its health checks and is part of the cluster. If the new node doesn’t show up here within a few minutes it’s time to shell in and try a restart.

## Upgrading a Clustered Instance

### Step 1: Build Image for New Version

To begin the upgrade process, we need to build the image for the upgrade version.

Navigate to [the packer directory](/builders/packer) and edit your `variables.auto.pkrvars.hcl` file so that the `looker_version` variable is set to the latest available version of Looker.

Build the image for the current version:

```
$ packer build .
```

### Step 2: Stop Looker Process

Upgrading a VM-based Looker instance involves downtime. To safely proceed we must stop the Looker process.

> Warning: Always keep in mind the most important rule of upgrading VMs: You can never have two versions of VM-based Looker connected to the same database. This will corrupt the database and render it unusable.

The quickest way to safely proceed is to “scale” our instance group to 0 nodes.

1. Navigate to [the clustered instance directory](/terraform/looker_clustered_instance)
2. Edit your `terraform.tfvars` file so `node_count` is set to `0`
3. Execute a `terraform apply` to roll out the change.

Wait for the old nodes to spin down. Go to **Compute Engine -> Instance Groups** in the GCP Console and confirm your nodes have stopped.

> Tip: If you pay attention to the Terraform plan you will notice that your instance templates will be updated to use the new image. This means when we spin your nodes back up they will use the updated image.

### Step 3: Back Up MySQL Database (optional)

Once your Looker nodes have come down you might want to take a snapshot of your MySQL database. This will ensure that if something goes wrong you can restore from a very recent backup. (Your database is automatically configured to take regular backups so this is purely optional depending on your RTO requirements)
1. Navigate to **CloudSQL** in the GCP Console and select your database.
2. Select “Backups” from the sidebar.
3. Click “Create Backup”.
4. In the modal, add a description and click “Create”.

### Step 4: Spin Up Clustered Instance for Current Version

1. Navigate back to [the clustered_instance directory](/terraform/looker_clustered_instance) and run:
2. Edit your `terraform.tfvars` file so `node_count` is set to `1`
3. Execute a `terraform apply` to roll out the change.

### Step 5: Confirm Current Version in Looker Instance
Once the Looker instance is ready, open a new browser tab and enter the web URL from your DNS. You should be presented with a Looker registration page. Use your Looker license key to register an initial user.

In your Looker instance click on the “Help” icon in the upper right corner. Confirm the version number is what you expect.

### Step 6: Scale Looker back up (if required)

If you were running multiple Looker nodes before the upgrade you can safely scale back to your original node count. Simply edit your `terraform.tfvars node count` variable to your desired node count and then execute another `terraform apply`.
