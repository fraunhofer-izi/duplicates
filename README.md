# Introduction

Utilities that help to find duplicate directories or files
on large filesystems using slurm if present. All files
will be hashed with sha256 in the process and results
are stored in text files to enable easy access and prevent
code injection.

## Files

We calculate hashes for all files with `sha256sum` and sort the result.
The output is in the form `size,sha256,file-path`.
Duplicate entries will be collected next to each other and
large files will be at the bottom.

## Directories

In order to identify duplicate directories, we concatenate the sorted
size, sha256 and name of all contained files and directories and apply sha256 o
the resulting string. That leaves us with a hash sum per directory. The result
will be sorted and filtered for duplicated hashes which identify
potentially duplicate directories and exclude all pairs of directories that
are not exactly identical.

# Instruction

Run `./update_file_hashes <dir1> <dir2> ...` to make or update the file hash
tables. This can be run by all users of the group (s. Group Usage) from
anywhere on the server. If you run the script without arguments, it reports the
state of any currently running hash update.

In order to use the tables to find duplicate
files or directories you can run `./update_dupes`.
This utility should only be run by the maintainer.

The scripts queue a slurm job if slurm is available that
that will wait for other jobs of the same repo.
You can run jobs locally with the option `--local` or `-l`.

Directories listed in `blacklist` are not included.

The result tables are explained below.

## Group Usage

If you want all members of a given group to be able to update the hash table
with `update_file_hashes`, write the group name to a file `group` in the
same directory as `update_file_hashes` and protect it from manipulation.

## Freeable space

After finding the duplicates estimate for the total amount of disc space that
could be saved by removing all duplicate files can be calculated with
`./sum_duplicate_size`.

## Missing Duplicates

By default, all sub-directories of directories, that have a duplicate, are
removed in `dupes.out` because they are duplicates
as well anyway. E.g., if `A` is a duplicate of `B` then all sub-dirs
, e.g., `A/a` and `B/a` are duplicates of one another and
will not be listed seperately.

However, sometimes there is an independent duplicate
of the sub-directory, e.g., `C/a` is a duplicate of `A/a` and `B/a`
but `C` is **not** a duplicate of `A`. Then only `C/a` will be listed
with no visible duplicate in `dubes.out`.

Worse, if `C` has another duplicate `D` the independent duplications
`A/a`=`B/a`=`C/a`=`D/a` will not be listed at all. But
the duplication of the super-directories `A`=`B` and `C`=`D` will be
listed. We consider this scenario to be a very rare case.

If you want to make sure a directory or file has no more duplicates you
are not aware of use `dupes_with_subs.out`!

## Disk Usage Utility

When all files are hashed one can us `du` to
quickly calculate the byte size of any directory or file
among the searched once with:
```{bash}
./du <dir1> <dir2> <dir3>/* ...
```
If `./update_dupes` was run recently you can use it with the
option `-q` or `--quick`. This works faster for large directories.

## Removing Directories

If you want to remove selected directories from the tables you can also
use the partial update scripts by setting the environment variable
`PURGE`. This will reomve the entries for `<dir1> <dir2> ...`:
```{bash}
PURGE=yes ./update_file_hashes <dir1> <dir2> ...
```

## Difference

Sometimes it is surprising that two very similar directories do not show up in
`dupes.out` and also have different hashes in `dir_hashes.out`.  For such
cases, you can use `diff` to find out why they differ. The utility gives you
all files that are unique in a set of directories.  To get all files that
occure only once either in `<dir1>` or `<dir2>` use
```{bash}
./diff <dir1> <dir2>
```
If two files with the same name are listed they probably differ in
the sub-directory possition, size or hash sum.

## Show Duplicates

One way is to browse the `human_dupes.out` result table where the largest
duplicates are listed first. If you want to list all duplicates of a given path
you can use the `./dupes` utility. It returns the duplicate files in the format
`<size>,<hash>,<path>`.
 - `./dupes <path1> <path2> ...` returns one line per duplicate file and the
   input path as a descriptive title to each set of duplicates. The returned
   duplicates do not include the given paths themselves.
 - `./dupes <tag1> <tag2> ...` returns all files with the given tag of the
   format `<size>,<hash>` and the tag as a descriptive title. This is much
   faster than using paths.
 - `./dupes <tag1>,<path1> <tag2>,<path2> ...` returns all duplicates of the
   given files. That does not include the given paths themselves and is as fast
   as using tags.
 - `./dupes -r <dir1> <dir2> ...` returns all files inside the given
   directories that have a hashed duplicate somewhere in the file system.

The listed formats of the arguments can also be mixed.

Instead of given arguments, you can also pipe them in. One use case is to
look for all duplicates **to** the non unique files in the given directories with
```{bash}
./dupes -r <dir1> <dir2> ... | ./dupes
```
and if you want to list all the duplicates including those inside the given
directories you can pass only the tags with
```{bash}
./dupes -r <dir1> <dir2> ... | cut -d , -f 1,2 | ./dupes
```

## Emulate sha256deep

The utility `./hashdeep <dir>` uses the table of hashed files to quickly emulate
the output of [sha256deep](http://md5deep.sourceforge.net/start-md5deep.html)
`sha256deep <dir>`.

## Logs

All calls of `update_file_hashes` and `update_dupes` are logged in `./update_logs/`.

# Result Tables

The results are used in some of the utilities above. Featured tables are:
 - `file_hashes.out` All hashed files in the format `<size in byte>,<sha256sum>,<path>`.
 - `sorted_file_hashes.out` Hashed files sorted by path in the format `<path>,<size in byte>,<sha256sum>`.
 - `dir_hashes.out` All directory hashes (available only after `update_dupes`).
 - `dupes.out` Duplicates without entries inside of duplicated directories.
 Sorted from large to small.
 - `human_dupes.out` As above with human readable sizes.
 - `dupes_with_subs.out` As `dupes.out` with **all** duplicate files and directiries
 and sorted with `LC_COLLATE=C` for fast lookup with the `./look` utility.


# Dependencies

All dependencies come with most linux distributions but the shipped version of
`look` from [bsdmainutils](https://packages.debian.org/de/sid/bsdmainutils)
often comes with a bug that does not allow to work with files larger than 2GB.
This repo comes with a patched version that was compiled on Ubuntu 18.04 x86_64.
If you have issues running it please compile your own patched
[bsdmainutils-look](https://github.com/stuartraetaylor/bsdmainutils-look)
and replace the file `./look` with your binary or a link to it.

Other dependencies and their version we teted with are
 - bash 4.4.20
 - bc 1.07.1
 - GNU Awk 4.1.4
 - GNU coreutils 8.28
 - GNU parallel 20161222
 - GNU sed 4.4
 - util-linux 2.31.1

If available we also support
 - slurm-wlm 17.11.2

# Note

We use GNU parallel:
*O. Tange (2018): GNU Parallel 2018, March 2018, https://doi.org/10.5281/zenodo.1146014.*

# Code Maintainer

The maintainer must be aware that filenames in Linux can contain any character
except the null `\x00` and the forward slash `/`. This can complicate the
processing of the hash tables and breaks many common text processing solutions
in rare cases. Since there are many users with many files on the system those
cases tend to exist.

Another curiosity is the output of `sha256` for wired filenames. You can test
this with `touch "a\b"; sha256 "a\b"`. The backslash in the filename is escaped
and strangely, the hash sum starts with a backslash which is not part of the
correct sum for files with size 0. This behavior is explained
[here](https://unix.stackexchange.com/questions/313733/various-checksums-utilities-precede-hash-with-backslash).

