#!/usr/bin/ruby
require 'logger'
ENV['EC2_PRIVATE_KEY'] = ''
ENV['EC2_CERT'] = ''
log = Logger.new('log/delete_unused_volumes.log')

available = "ec2-describe-volumes | grep available | awk '{print \$2}'"
list = `#{available}`
list.each do |volume|
  delete = "ec2-delete-volume " + volume.chomp
  log.info(delete)
  puts delete
  `#{delete}`
end
