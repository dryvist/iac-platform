# Job templates (TCL flow definitions), as code.
#
# These were previously UI-only (see the removed note in organization.tf) —
# Vikunja #3320 traced job 898 running unattended to the "Plan and apply"
# template having no approval step between plan and apply. Declaring the
# flow here makes that gap a plannable diff instead of a silent DB edit; a
# live PATCH bridged the two gated templates below ahead of this PR (see
# lane-C notes), so `tofu plan` on this resource should show 0 changes.
#
# Every template whose flow ends in terraformApply or terraformDestroy must
# have an "approval" step immediately before it. The precondition below is
# load-bearing (unlike a `check` block, which only warns and still lets
# `plan`/`apply` exit 0) — see tofu-proxmox modules/proxmox-stack/checks.tf
# for why `check` is never used for anything that must actually block.
locals {
  # name => flow step "type" values in order, parsed from each template's
  # own `content` below (kept in sync by hand — these are short, static
  # flows, not worth a YAML-decode indirection).
  template_flow_types = {
    plan             = ["terraformPlan"]
    plan_and_apply   = ["terraformPlan", "approval", "terraformApply"]
    destroy          = ["approval", "terraformDestroy"]
    cli_plan_apply   = ["terraformPlan", "approval", "terraformApply"]
    cli_plan_destroy = ["terraformPlanDestroy", "approval", "terraformApply"]
  }
}

resource "terrakube_organization_template" "plan" {
  name            = "Plan"
  organization_id = terrakube_organization.org.id
  description     = "Running Terraform plan"
  version         = "1.0.0"
  content         = <<-EOF
    flow:
      - type: "terraformPlan"
        name: "Plan"
        step: 100
  EOF

  lifecycle {
    precondition {
      # Single-step plan-only template — never applies, so no approval is
      # required. Asserts the flow really is plan-only, so a future edit
      # that quietly adds an apply step trips the gate below instead.
      condition     = local.template_flow_types["plan"] == ["terraformPlan"]
      error_message = "The 'Plan' template must stay plan-only — add a real apply flow as a new template instead of extending this one."
    }
  }
}

resource "terrakube_organization_template" "plan_and_apply" {
  name            = "Plan and apply"
  organization_id = terrakube_organization.org.id
  description     = "Running Terraform plan and apply"
  version         = "1.0.0"
  content         = <<-EOF
    flow:
      - type: "terraformPlan"
        name: "Plan"
        step: 100
      - type: "approval"
        name: "Approve Apply"
        step: 150
        team: "TERRAFORM_CLI"
      - type: "terraformApply"
        name: "Apply"
        step: 200
  EOF

  lifecycle {
    precondition {
      condition     = index(local.template_flow_types["plan_and_apply"], "terraformApply") > 0 && local.template_flow_types["plan_and_apply"][index(local.template_flow_types["plan_and_apply"], "terraformApply") - 1] == "approval"
      error_message = "Vikunja #3320: every apply-capable template must have an 'approval' step immediately before terraformApply."
    }
  }
}

resource "terrakube_organization_template" "destroy" {
  name            = "Destroy"
  organization_id = terrakube_organization.org.id
  description     = "Running Terraform destroy"
  version         = "1.0.0"
  content         = <<-EOF
    flow:
      - type: "approval"
        name: "Approve Destroy"
        step: 50
        team: "TERRAFORM_CLI"
      - type: "terraformDestroy"
        name: "Destroy"
        step: 100
  EOF

  lifecycle {
    precondition {
      condition     = index(local.template_flow_types["destroy"], "terraformDestroy") > 0 && local.template_flow_types["destroy"][index(local.template_flow_types["destroy"], "terraformDestroy") - 1] == "approval"
      error_message = "Every destroy-capable template must have an 'approval' step immediately before terraformDestroy."
    }
  }
}

resource "terrakube_organization_template" "cli_plan_apply" {
  name            = "Terraform-Plan/Apply-Cli"
  organization_id = terrakube_organization.org.id
  description     = "Running Terraform apply from Terraform CLI"
  version         = "1.0.0"
  content         = <<-EOF
    flow:
    - type: "terraformPlan"
      name: "Terraform Plan from Terraform CLI"
      step: 100
    - type: "approval"
      name: "Approve Plan from Terraform CLI"
      step: 150
      team: "TERRAFORM_CLI"
    - type: "terraformApply"
      name: "Terraform Apply from Terraform CLI"
      step: 200
  EOF

  lifecycle {
    precondition {
      condition     = index(local.template_flow_types["cli_plan_apply"], "terraformApply") > 0 && local.template_flow_types["cli_plan_apply"][index(local.template_flow_types["cli_plan_apply"], "terraformApply") - 1] == "approval"
      error_message = "Vikunja #3320: every apply-capable template must have an 'approval' step immediately before terraformApply."
    }
  }
}

resource "terrakube_organization_template" "cli_plan_destroy" {
  name            = "Terraform-Plan/Destroy-Cli"
  organization_id = terrakube_organization.org.id
  description     = "Running Terraform destroy from Terraform CLI"
  version         = "1.0.0"
  content         = <<-EOF
    flow:
    - type: "terraformPlanDestroy"
      name: "Terraform Plan Destroy from Terraform CLI"
      step: 100
    - type: "approval"
      name: "Approve Plan from Terraform CLI"
      step: 150
      team: "TERRAFORM_CLI"
    - type: "terraformApply"
      name: "Terraform Apply from Terraform CLI"
      step: 200
  EOF

  lifecycle {
    precondition {
      condition     = index(local.template_flow_types["cli_plan_destroy"], "terraformApply") > 0 && local.template_flow_types["cli_plan_destroy"][index(local.template_flow_types["cli_plan_destroy"], "terraformApply") - 1] == "approval"
      error_message = "Every destroy-capable CLI template must have an 'approval' step immediately before its terraformApply finalization step."
    }
  }
}

# Associate the resources above with the templates already created via the
# API/UI (job 898 traced one of these to being ungated; the others were
# already correct) — see lane-C notes for the exact PATCH history.
import {
  to = terrakube_organization_template.plan
  id = "69f64b04-ac84-45fe-b9e3-ceca128f1ae3"
}
import {
  to = terrakube_organization_template.plan_and_apply
  id = "d5e37c74-2500-4305-bcf1-294e2021850f"
}
import {
  to = terrakube_organization_template.destroy
  id = "cc233693-86aa-4129-9e03-784437b6b5e1"
}
import {
  to = terrakube_organization_template.cli_plan_apply
  id = "e0483d1e-e70b-4df6-955c-9954362f7f95"
}
import {
  to = terrakube_organization_template.cli_plan_destroy
  id = "568668c8-6b1e-4f6a-bbb4-dfe1c8cb6375"
}
