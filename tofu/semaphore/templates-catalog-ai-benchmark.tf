# ansible-proxmox-ai benchmark templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_ai_benchmark = {
    # Run fixed suites against an already-converged engine from a tagged
    # benchmark client. Raw output remains on the selected node for collection
    # and workstation publication.
    ai-benchmark-run = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/benchmark-run.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      rail_sec         = 3600
      survey_vars = [
        {
          name        = "node"
          title       = "Node"
          description = "Published Proxmox inventory name for the selected client."
          required    = true
          type        = "string"
        },
        {
          name        = "client_vmid"
          title       = "Client VMID"
          description = "VMID of a running LXC tagged benchmark-client."
          required    = true
          type        = "string"
        },
        {
          name        = "gpu_guest_vmid"
          title       = "GPU guest VMID"
          description = "VMID of the measured GPU guest whose package versions are recorded."
          required    = true
          type        = "string"
        },
        {
          name        = "engine_url"
          title       = "Engine URL"
          description = "OpenAI-compatible /v1 endpoint without credentials or query parameters."
          required    = true
          type        = "string"
        },
        {
          name        = "model"
          title       = "Model"
          description = "Model identifier accepted by the selected engine."
          required    = true
          type        = "string"
        },
        {
          name        = "tokenizer"
          title       = "Tokenizer"
          description = "Tokenizer identifier used to interpret request lengths."
          required    = true
          type        = "string"
        },
        {
          name        = "suite"
          title       = "Suite"
          description = "bigcodebench-hard, promptfoo-<suite>, or one fixed-length vllm-sweep cell."
          required    = true
          type        = "string"
        },
        {
          name        = "items_file"
          title       = "Suite input file"
          description = "Immutable raw GitHub config URL for Promptfoo; blank for BigCodeBench."
          required    = false
          type        = "string"
        },
        {
          name        = "reasoning_arm"
          title       = "Reasoning arm"
          description = "Explicit model reasoning template arm."
          required    = true
          type        = "enum"
          enum_values = {
            off   = "off"
            low   = "low"
            xhigh = "xhigh"
          }
        },
        {
          name        = "concurrency"
          title       = "Concurrency"
          description = "Positive suite request concurrency."
          required    = true
          type        = "string"
        },
        {
          name        = "max_tokens"
          title       = "Maximum output tokens"
          description = "Positive maximum generation length per request."
          required    = true
          type        = "string"
        },
        {
          name        = "sandbox_pool"
          title       = "Sandbox pool size"
          description = "BigCodeBench sandbox worker count; must cover concurrency."
          required    = true
          type        = "string"
        },
        {
          name        = "input_tokens"
          title       = "Fixed-length input tokens"
          description = "Positive input length for a vLLM serving cell; ignored by other suites."
          required    = false
          type        = "string"
        },
        {
          name        = "request_rate"
          title       = "Request rate"
          description = "inf for batched load or a positive rate for staggered Poisson load."
          required    = false
          type        = "string"
        },
        {
          name        = "num_prompts"
          title       = "Prompt count"
          description = "Positive number of requests for a vLLM serving cell."
          required    = false
          type        = "string"
        },
        {
          name        = "seed"
          title       = "Random seed"
          description = "Unique numeric seed for this vLLM serving cell."
          required    = false
          type        = "string"
        },
        {
          name        = "run_id"
          title       = "Run ID"
          description = "Unique safe identifier used for output paths and tags."
          required    = true
          type        = "string"
        },
        {
          name        = "upgrade"
          title       = "Upgrade guest OS"
          description = "Run full-upgrade on the measured GPU guest before this cell; leave false after the block's first cell."
          required    = false
          type        = "enum"
          enum_values = {
            "true"  = "true"
            "false" = "false"
          }
        },
        {
          name        = "publish"
          title       = "Publish results"
          description = "Must remain false; publish from the workstation after review."
          required    = false
          type        = "enum"
          enum_values = {
            "false" = "false"
            "true"  = "true"
          }
        },
      ]
      description = "Run BigCodeBench-Hard or a pinned Promptfoo suite in a tagged client and archive raw results on its node."
    }

  }
}
