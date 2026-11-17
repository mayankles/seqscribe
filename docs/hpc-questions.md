# Questions for HPC staff

Context to give them: a Shiny app (R) that needs to talk to a large language
model served on the cluster over an OpenAI-compatible HTTP API. Nothing leaves
the cluster. The preferred setup is the model server and the app on the same
node.

## Launching the app

1. Which system launches user Shiny apps (Open OnDemand or something else)?
2. Can that job request a GPU, and choose its memory, cores and walltime?
3. Can the job run a custom startup script before the app starts (to launch
   the model server)?
4. Is the app served under a sub-path behind a proxy? Any websocket limits or
   idle timeouts?

## Running the model

5. Which GPUs are available, with how much memory, and what are typical wait
   times for an interactive GPU job?
6. Is there an existing, supported way to run LLM inference on the cluster
   (a module, a container, a shared service)?
7. Is Apptainer/Singularity available for running a server such as llama.cpp
   or vLLM?
8. Where should large model files live (scratch, project space), and are there
   quotas to plan for?

## Networking and security

9. If the model has to run as a separate job: can compute nodes reach each
   other on arbitrary ports?
10. Any policy on user-run network services on compute nodes? (The server
    would require an API key and bind only where needed.)
11. Do compute nodes have outbound internet access (for GEO downloads and
    package installs), or should everything be staged from a login node?

## Software

12. Recommended way to provide R and Bioconductor packages: modules, a
    personal library, renv, or a container?
13. Can the app itself submit jobs with `sbatch` from inside the Shiny job?
