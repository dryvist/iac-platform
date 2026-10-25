# Read-only hardware fact gathering, kept in its own file because
# templates-catalog-proxmox.tf is at the 12KB File Size gate. Entries here follow
# the field docs in templates-catalog.tf and the shape of the pre-flight entries
# in templates-catalog-proxmox.tf.

locals {
  ansible_templates_proxmox_facts = {
    hardware-facts = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/hardware-facts.yml"
      limit            = "all"
      mutating         = false
      schedule_enabled = false
      extra_args       = []
      survey_vars = [
        {
          name        = "hardware_facts_hosts"
          title       = "Hosts"
          description = "Inventory host name or group to read."
          required    = true
          type        = "string"
        },
        {
          name        = "hardware_facts_categories"
          title       = "Categories"
          description = "Comma-separated: board, cpu, memory, pci, disks, gpus, psu, pools. Empty reads all."
          required    = false
          type        = "string"
        },
        {
          name        = "hardware_facts_output"
          title       = "Output"
          description = "report prints to the task log; artifact also writes one JSON file on the controller."
          required    = true
          type        = "enum"
          enum_values = {
            report   = "report"
            artifact = "artifact"
          }
        },
      ]
      description = "Read-only board, CPU, memory, PCI, GPU, drive, power-supply and pool facts for any inventory host or group."
    }
  }
}
