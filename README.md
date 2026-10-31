# opencode-config

**opencode-config** is how I use opencode to do agentic development

---

## Why opencode-config?
I want to have a system that I can improve and take with me wherever I go

## Requirements

| Dependency | Required? | Why | Install |
|---|---|---|---|
| [node](https://nodejs.org) | ✅ Yes | Used for opencode 2.0 plugins| [Install node](https://nodejs.org/en/download) |
| [bun](https://bun.com/) | ✅ Yes | Used for opencode 2.0 plugins| [Install bun](https://bun.com/docs/installation) |
| [llama.cpp](https://llama-cpp.com) | ✅ Yes | Used for graphicle ask| [Install .llama.cpp](https://llama-cpp.com/getting-started/#how-to-install-llama-cpp-on-your-mac) |
| [graphicle](https://github.com/Graphicle-AI/graphicle) | ✅ Yes | Used as context memory store | [Install graphicle](https://github.com/Graphicle-AI/graphicle#quick-start) |

---

## Getting started

### 0. Set up a sandbox to test
I am a fan of [devpod](https://devpod.sh).  To test this in a sandbox:
- Create a sandbox `devpod up --open-ide=false alpine/git`
- ssh to the sandbox `ssh git.devpod`
- clone the repo `git clone https://github.com/passionateprogrammersguild/opencode-config.git`
- run the script `cd opencode-config/ && ./install.sh`
- run opencode `. /etc/profile && opencode`

## License

opencode-config is licensed under the [MIT License](LICENSE). Third-party dependencies remain under their own licenses — see their respective NuGet/npm pages for details.

---