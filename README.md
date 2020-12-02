# notable_cli

## Usage

### List notes

List all notes:

```sh
notable_cli ls
```

List all notes containing `regexp` in title:[^1]

[^1]: Or file name?

```sh
notable_cli ls title
```

List all notes in a particular notebook:

```sh
notable_cli ls --notebook=Notebook
```

List all notes containing certain tags:

```sh
notable_cli ls --tag=tag1 --tag=tag2
```

List all notes in particular notebook with tags and containing certain string i title:

```sh
notable_cli ls --notebook=Notebook --tag=tag1 title
```

### Attachments

```sh
notable_cli attachment list [title]
```

```sh
notable_cli attachment lost
```

```sh
notable_cli attachment orphaned
```