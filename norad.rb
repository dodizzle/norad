#!/usr/bin/env ruby
require 'delayed_job_priorities.rb'
require 'rubygems'
require 'mysql'

ssh_key = ''
hostname = ''
username = ''
password = ''
databasename = ''
all_low_count = '1'
job_count = '5'

$my = Mysql.new(hostname, username, password, databasename)

def get_job_counts()
counts = Array.new
select = 'SELECT priority, COUNT(priority) FROM delayed_jobs WHERE run_at < NOW() AND priority!=\'100\' GROUP BY priority HAVING COUNT(priority) > 5'
rs = $my.query(select)
   while row = rs.fetch_row do
	counts.push(row[0] + "|" + row[1])	
   end
   return counts
end

def get_names_counts(counts)
 rr = Array.new
 counts.each do |line|
  priority,count = line.split('|')
  job_name =  DELAYED_JOB_PRIORITIES.invert[priority.to_i]
  rr.push(job_name.to_s + "|" + count.to_s)
 end
return rr
end

def get_divide_by(name)
q = Hash.new
 q = {
    "mixpanel"                 => 5000,
    "blog_import"             => 200,
    "blog_import_flickr"       => 200,
    "blog_import_merge"        => 200,
    "autopost"                 => 200,
    "autopost_slow"            => 200,
    "utility"                  => 200,
    "content_part"            => 200,
    "blog_import_content_part" => 200,
    "blog_import_post_create"  => 200,
    "pingpost"                 => 1000,
    "geocode"                  => 1000,
    "transcode"               => 200,
    "delayed_publish"         => 1000,
    "xmlrpc_ping"              => 5000,
    "postprocess"              => 1000,
    "notification_email"       => 1000
  }

  divide_by = q[name]
  return divide_by
end

def  set_node_count(names_counts)
ss = Array.new
names_counts.each do |line|
	name,count = line.split('|')
	divide_by = get_divide_by(name)
	foo = count.to_i / divide_by.to_i
	if foo.to_i > 0
		ss.push(name + "|" + foo.to_i.to_s)
	end
end
return ss
end

def launch_nodes(names_and_nodes,job_count)
names_and_nodes.each do |line|
	name,count = line.split('|')
	cmd = "./control_delayed_jobs.rb --action launch --number " + count + " --job_name " + name + " --job_count " + job_count + "\""
	puts cmd
	`#{cmd}`
end
end

# this will launch all_low nodes only regardless of what other nodes are spawned
def launch_all_low(all_low_count,job_count)
       cmd = "./control_delayed_jobs.rb --action launch --number " + all_low_count + " --job_count " + job_count + " --job_name all_low\""
      puts cmd
       `#{cmd}`
end

def kill_running_nodes()
  cmd = "./control_delayed_jobs.rb --action kill-all\""
  puts cmd
  `#{cmd}`
  sleep 60
  clean = "./delete_unused_volumes.rb"
  puts clean
  `#{clean}`
end

kill_running_nodes()
counts = get_job_counts()
names_counts = get_names_counts(counts)
names_and_nodes = set_node_count(names_counts)
puts names_and_nodes
launch_nodes(names_and_nodes,job_count)
launch_all_low(all_low_count,job_count)
