# zbox

core unix utilities reimplemented in zig

## motivation

the rust ecosystem has uutils which provides a modern reimplementation of gnu coreutils  
embedded systems rely on busybox but its written in c with all the associated memory safety issues  
no one has built a comprehensive alternative using a modern systems language like zig  
this project aims to fill that gap by providing memory safe coreutils with zero runtime overhead

## what is this

zbox is a single multicall binary that can behave as different unix utilities depending on how its invoked  
you can either call it directly with a command name or symlink it to create individual utility binaries  
the goal is to eventually implement most of the posix standard utilities while maintaining compatibility  

currently implemented utilities:
- echo - display text
- cat - concatenate and display files  
- ls - list directory contents
- mkdir - create directories
- rm - remove files and directories
- cp - copy files and directories

## features

memory safe implementation in zig with compile time safety guarantees  
single static binary with zero dependencies  
works as multicall binary or individual symlinked utilities  
compatible with standard unix behavior and exit codes  
small binary size suitable for embedded systems  
cross platform support anywhere zig runs

## building and usage

```bash
# clone and build
git clone <repo>
cd zbox
zig build

# use as multicall binary
./zig-out/bin/zbox echo hello world
./zig-out/bin/zbox cat /etc/passwd
./zig-out/bin/zbox ls -l /tmp
./zig-out/bin/zbox mkdir -p some/deep/path
./zig-out/bin/zbox rm -rf unwanted_dir
./zig-out/bin/zbox cp -r source_dir dest_dir

# create symlinks for individual utilities
cd /usr/local/bin
ln -s /path/to/zbox echo
ln -s /path/to/zbox cat
ln -s /path/to/zbox ls
ln -s /path/to/zbox mkdir
ln -s /path/to/zbox rm
ln -s /path/to/zbox cp

# now use them like normal
echo hello world
cat myfile.txt
ls /home
mkdir newdir
rm old_file
cp important.txt backup.txt
```

## project status

this is early stage development  
only basic utilities are implemented so far  
contributions welcome for additional utilities  
see issues for planned features

## license

[BSD 2-Clause License](LICENSE)