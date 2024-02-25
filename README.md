### Readme

Simple, zero-dependencies ruby script to create ipset blockist using [ipsum](https://github.com/stamparm/ipsum/) lists.

#### Running

Run `ruby ipsum-blocker.rb` to run with default options, or pass `-h` to see available options.

#### Installation

1. Drop the script in `/opt`.


#### Schedule using systemd

1. Drop systemd files in `/etc/systemd/system`
2. Edit files to make desired changes, such as updating schedule or changing script options, path etc.
3. Run `systemctl daemon-reload`
4. Run `systemctl enable ipsum-blocker-rb.timer`
