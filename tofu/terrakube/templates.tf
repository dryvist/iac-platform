# Job templates (TCL flow definitions), as code.
#
# Every template whose flow ends in terraformApply or terraformDestroy must
# have an "approval" step immediately before it. The precondition below is
# load-bearing (unlike a `check` block, which only warns and still lets
# `plan`/`apply` exit 0) and reads the decoded content itself — not a
# hand-kept summary — so an edit to a template's flow that drops its
# approval step fails plan.
locals {
  templates = {
    plan = {
      name        = "Plan"
      description = "Running Terraform plan"
      # chomp(): the live template has no trailing newline (single-step
      # flows only) — every other template below does.
      content = chomp(<<-EOF
        flow:
          - type: "terraformPlan"
            name: "Plan"
            step: 100
      EOF
      )
    }
    plan_and_apply = {
      name        = "Plan and apply"
      description = "Running Terraform plan and apply"
      content     = <<-EOF
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
    }
    destroy = {
      name        = "Destroy"
      description = "Running Terraform destroy"
      content     = <<-EOF
        flow:
          - type: "approval"
            name: "Approve Destroy"
            step: 50
            team: "TERRAFORM_CLI"
          - type: "terraformDestroy"
            name: "Destroy"
            step: 100
      EOF
    }
    cli_plan_apply = {
      name        = "Terraform-Plan/Apply-Cli"
      description = "Running Terraform apply from Terraform CLI"
      content     = <<-EOF
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
    }
    cli_plan_destroy = {
      name        = "Terraform-Plan/Destroy-Cli"
      description = "Running Terraform destroy from Terraform CLI"
      content     = <<-EOF
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
    }
  }

  # Flow steps in step order, decoded from each template's own content — not
  # a hand-kept summary — so an edit to a template's flow is reflected here
  # without depending on YAML list ordering (Terrakube TCL is authored in
  # step order, but sort explicitly rather than relying on that).
  template_ordered_types = {
    for key, t in local.templates :
    key => [
      for pair in sort([
        for s in yamldecode(t.content).flow : "${format("%05d", s.step)}|${s.type}"
      ]) : split("|", pair)[1]
    ]
  }

  template_apply_or_destroy_gated = {
    for key, types in local.template_ordered_types :
    key => alltrue([
      for i, type in types :
      type != "terraformApply" && type != "terraformDestroy" || (i > 0 && types[i - 1] == "approval")
    ])
  }
}

resource "terrakube_organization_template" "this" {
  for_each = local.templates

  name            = each.value.name
  organization_id = terrakube_organization.org.id
  description     = each.value.description
  version         = "1.0.0"
  content         = each.value.content

  lifecycle {
    precondition {
      condition     = local.template_apply_or_destroy_gated[each.key]
      error_message = "Every terraformApply/terraformDestroy step in this template's flow must be immediately preceded by an approval step."
    }
  }
}

import {
  to = terrakube_organization_template.this["plan"]
  id = "${terrakube_organization.org.id},69f64b04-ac84-45fe-b9e3-ceca128f1ae3"
}
import {
  to = terrakube_organization_template.this["plan_and_apply"]
  id = "${terrakube_organization.org.id},d5e37c74-2500-4305-bcf1-294e2021850f"
}
import {
  to = terrakube_organization_template.this["destroy"]
  id = "${terrakube_organization.org.id},cc233693-86aa-4129-9e03-784437b6b5e1"
}
import {
  to = terrakube_organization_template.this["cli_plan_apply"]
  id = "${terrakube_organization.org.id},e0483d1e-e70b-4df6-955c-9954362f7f95"
}
import {
  to = terrakube_organization_template.this["cli_plan_destroy"]
  id = "${terrakube_organization.org.id},568668c8-6b1e-4f6a-bbb4-dfe1c8cb6375"
}
