# Notable.pm and notable_cli

This is a simple Perl module and command line interface to access and manipulate [Notable](https://notable.app) markdown notes.

Currently, it barely works, but please add requests on what kind of functionality you would like to find in a tool like this. I want it to be able to do things like:

- Listing notes based on title, notebooks, tags or any combination of them.
- Find orphaned attachments.
- Find broken links to renamed or non-existing attachments.
- Automatically add inline links to attached images.
- Print notes using [Pandoc](https://pandoc.org).

## Usage

### List notes

List all notes:

```sh
notable_cli ls
```

List all notes containing `regexp` in title:

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

