<img src="./icon.png" width="128" />

# 1password-csv-fix

### What

This is a commandline tool to identify and correct invalid URLs in your 1Password vault. It's designed to be run from a Terminal. I built and tested it on macOS, but it should run on Windows or Linux as well with little or no modification.

The script can identify vault items that have invalid (merged) comma-separated URLs, such as:

```
https://mysite1.foo,http://10.20.30.40,https://myotherurl.foo
```

It can repair these items, splitting the URLs back into separate fields so that autofill works properly.

### Why

This can happen after an export/import from another tool (in my case Bitwarden), due to the differing formats and capabilities of the password managers, combined with the limitations of the CSV format. See [this thread][3] from the 1Password forum for example.

### How

#### Installation

Download the [latest release][5] and place the `1password-csv-fix.sh` file in your system's `$PATH`. I recommend `/usr/local/bin`, but anywhere will do.

There are some prerequisites that need to be installed:

- `bash` shell - built into macOS & Linux, on Windows use [WSL][4] (`wsl --install`)
- [`op`][2] - official 1Password CLI
- [`jq`][1] - for JSON processing
- [`fzf`][6] - for selecting and acting on multiple items

_(if any of these are missing, the script will notify you and abort)_

#### Usage

Open a Terminal and run `1password-csv-fix.sh`. Without any arguments (or with `-h/--help`), the helptext will be displayed:

```
$ 1password-csv-fix.sh -h
usage: 1password-csv-fix.sh [opts]
    -a,--all                  show all items (tab-separated: ID, Name, URL)
    -g,--get                  get JSON for a single item
    -s,--search <query>       search (regex, within URL)
    -o,--open <item>          open item in 1Password UI
    -e,--edit [item]          edit item in 1Password UI (use `last` for most recent)
    -u,--urls [item]          show URLs (if no item arg is supplied, show all)
    -l,--long                 list items with invalid CSV URLs
    -r,--raw                  raw JSON output of `item list`
    --fix <item>              repair invalid comma-separated URLs from CSV import
    --fix-multi               use fzf to select multiple items (to fix)
    --del-multi               use fzf to DELETE multiple items
    --del-field <fieldname>   recursively remove a field (if empty) from multiple items
```

To **fix** a single item (pass the item ID as the argument):

```
1password-csv-fix.sh --fix zyauxs3ataermfxiv7qaaznmrq
```

To fix **multiple items** at once (if there are no invalid URLs detected, this will be a no-op):

```
1password-csv-fix.sh --fix-multi
```

#### ⚠️ Danger Zone ⚠️

To **delete** fields (e.g. if an unused field is left over after an import):

```
1password-csv-fix.sh --del-field <fieldname>
```

To **delete** entire item(s) from the vault:

```
1password-csv-fix.sh --del-multi
```

### Help

I've used this to repair hundreds of items and it has worked well, but there could always be edge cases. As with *any* 3rd party tool, please use caution and make sure you have a good [backup][7] of your vault in case something goes wrong.

Feel free to reach out on the forum or file an [issue][8] if you run into a problem!

[1]: https://jqlang.github.io/jq/download/
[2]: https://1password.com/downloads/command-line
[3]: https://1password.community/discussion/145700/how-to-create-a-login-item-with-2-urls
[4]: https://learn.microsoft.com/en-us/windows/wsl/install
[5]: https://github.com/luckman212/1password-csv-fix/releases
[6]: https://github.com/junegunn/fzf
[7]: https://support.1password.com/export/
[8]: https://github.com/luckman212/1password-csv-fix/issues
