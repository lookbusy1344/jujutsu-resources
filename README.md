# Useful Jujutsu version control links

Jujutsu (jj) is a great new version control system. It uses git as a storage layer, so works with all git forges, your collegues can continue with vanilla git, and your existing tools will continue to work (although it's safest not to write with git tools, just read). If you don't like jj, just delete the `.jj` folder and your repo is vanilla git again!

To convert a local git repo just run `jj git init`. That's it.

I'm not here to sell you jj, there are lots of excellent resources to do that. This is just one place for all the resources I use.

##  Jujutsu (jj) version control

https://github.com/jj-vcs/jj

https://www.jj-vcs.dev/latest/

### Steve’s jujutsu tutorial

https://steveklabnik.github.io/jujutsu-tutorial/

### My updated version of Steve’s tutorial

Steve's tutorial hasn't been updated in about 12 months, so this is an update version for the latest jj. Also available as a pdf for offline reading.

https://lookbusy1344.github.io/jujutsu-tutorial/

https://github.com/lookbusy1344/jujutsu-tutorial

### Jjui (TUI like lazygit)

https://github.com/idursun/jjui

### Jayjay GUI (Swift and cross platform)

https://github.com/hewigovens/jayjay

https://jayjay.hewig.dev

### VsCode plugin

https://marketplace.visualstudio.com/items?itemName=jjx.jjx

### JetBrains plugin

https://plugins.jetbrains.com/plugin/30576-jujutsu-vcs-integration

When using this plugin, ensure your `vcs.xml` is properly set for Jujutsu:

```
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="VcsDirectoryMappings">
    <mapping directory="$PROJECT_DIR$" vcs="Jujutsu" />
  </component>
</project>
```

### Skill for AI

This will help teach your AI about using jj:

[skill/jj-version-control](skill/jj-version-control/)

### User level Claude / Codex comment:

You need to tell your agents to probe repos and ensure jj repos use `jj` commands. Put this in your user level `CLAUDE.md` or `AGENTS.md`:

- Before the first VCS command, run `jj --ignore-working-copy root` as a command of its own. Do not chain it with other commands: a later failure hides its exit status. If jj succeeds, use jj for all VCS commands. Do not run git on jj repos. You have a skill for jj version control.


### Repo config for AI, pre-commit and pre-push

jj lacks hooks (because committing is implicit and automatic) so it's a good idea to configure your agent with pre-commit and pre-push rules. Here's an example:

todo

Or checkout these repos for working examples:

#### .NET example

https://github.com/lookbusy1344/RecordValueAnalyser

#### Rust example

https://github.com/lookbusy1344/HashRust

#### Go/mixed example

https://github.com/lookbusy1344/arm_emulator
