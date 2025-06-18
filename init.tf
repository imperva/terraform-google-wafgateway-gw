data "template_cloudinit_config" "gw_gcp_deploy" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/x-shellscript"
    content      = <<-EOF
      #! /bin/bash
      LOG_FILE=/var/log/gcp_gdm.log
      DEPLOYED=/opt/SecureSphere/gcp/bin/deployed
      sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
      [google-cloud-sdk]
      name=Google Cloud SDK
      baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
      enabled=1
      gpgcheck=1
      repo_gpgcheck=0
      gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
            https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
      EOM
      sudo yum install google-cloud-sdk -y    
      if  [ ! -f "$DEPLOYED" ]; then
        if MX_PASSWORD=$(gcloud secrets versions access latest --secret="${local.mx_secret_id}" 2>&1); then
          /opt/SecureSphere/gcp/bin/gcp_deploy --component=Gateway --password=$MX_PASSWORD --product=WAF --timezone=${var.timezone} --gateway_group=${local.gw_group} --management_ip=${local.management_ip} --model_type=${var.model} --gateway_mode=reverse-proxy-hades --scaling=${local.is_autoscaling} || exit 1    
          touch "$DEPLOYED"
        else
          echo "ERROR: Could not fetch MX password from Secret Manager - Terraform user must be a Secret Admin to assign secretAccessor permissions for this instance's service account" >> $LOG_FILE
        fi
      else
        echo "Already deployed.." 
      fi
    EOF
  }
}