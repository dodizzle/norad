#!/usr/bin/env ruby

require 'net/smtp'
require 'optparse'
require 'logger'
###################
# AWS credentials #
###################
ENV['EC2_PRIVATE_KEY'] = '.pem'
ENV['EC2_CERT'] = '.pem'
$log = Logger.new('log/aws.log')
#########################
# spot instance options #
#########################
instancesize = 'm1.large'
# old
ami = ''
group = ''
os = 'Linux/UNIX'
################
# mail options #
################
from = ""
from_alias = "norad"
to = ""
to_alias = "norad"
subject = "norad "
##################
# define options #
##################
options = {}

optparse = OptionParser.new do|opts|
   opts.banner = "Usage: " + $0 + "--action [launch|terminate] --number --job_name"

   opts.on( '--action ACTION', 'launch or terminate' ) do|action|
      options[:action] = action
   end

   opts.on( '--number #', 'number of instances' ) do|number|
      options[:number] = number
   end

   opts.on( '--job_name NAME', 'name of delayed_job' ) do|job_name|
      options[:job_name] = job_name
   end

   opts.on( '--job_count COUNT', 'number of jobs per host' ) do|job_count|
      options[:job_count] = job_count
   end

   opts.on( '--help', 'Display this screen' ) do
      puts opts
      exit
   end

   optlength = ARGV.length
   if optlength < 1
      puts opts
      exit
   end

end

optparse.parse!

action = options[:action]
job_count = options[:job_count]
job_name = options[:job_name]
numberofinstances = options[:number]
###########
# methods #
###########
def get_bidding_price(instancesize,os)
   prices = Array.new
   tp = Array.new
   time = Time.new
   day = time.strftime("%Y-%m-%d")
   hour = "T00:00:00"
   start = day + hour

   sum = 0.0
   command = "ec2-describe-spot-price-history -t " + instancesize + "  -d " + os + "  -s " + start
   puts command
   $log.info(command)
   answer = `#{command}`
   prices = answer.split(/\n/)
   prices.each do |p|
      type,price,timestamp,instancetype,description = p.split(/\s/)
      sum += price.to_f
      tp.push(price)
   end

   average = sum / tp.length.to_f
   bid = average * 2.250
   return bid
end

def request_spot_instance(ami,instancesize,group,numberofinstances,bid,job_name,job_count)
   foo = Array.new
   command = "ec2-request-spot-instances " + ami + " -d delayed_job=" + job_name + ",job_count=" + job_count.to_s + " -t " + instancesize + " -r one-time -g " + group + " -n " + numberofinstances.to_s + "  -r us-east-1 -p " + bid.to_s
   puts command
   $log.info(command)
   request = `#{command}`
   name,spot,foo = request.split(/\s/)
   return spot
end

def get_ids_by_tag(job_name)
    ids =  Array.new
    command = "ec2-describe-instances | grep " + job_name + " | awk '{print \$3}'"
    $log.info(command)
    ids = `#{command}`
    ids = ids.gsub(/\n/,' ')
    return ids
end    

def get_sirs_by_tag(job_name)
    sirs = Array.new
    command = "ec2-describe-instances | grep " + job_name + " | awk '{print \$3}'"
    ids = `#{command}`
    ids.each do |id|
	cmd = "ec2-describe-spot-instance-requests| grep "  + id.chomp + " |awk '{print \$2}'"
	$log.info(cmd)
	sir = `#{cmd}`
        sirs.push(sir.chomp)
    end
	sirs = sirs.join(' ')
    return sirs
end

def cancel_spot_requests(sirs)
	cancel = "ec2-cancel-spot-instance-requests " + sirs
	puts cancel
	$log.info(cancel)
	`#{cancel}`
end

def terminate_instances(ids)
	command = "ec2-terminate-instances " + ids
	$log.info(command)
	puts command
	`#{command}`
end

def launch_instances(ami,instancesize,group,numberofinstances,os,job_name,job_count)
                bid = get_bidding_price(instancesize,os)
                spot = request_spot_instance(ami,instancesize,group,numberofinstances,bid,job_name,job_count)
end

def terminate(job_name)
    ids = get_ids_by_tag(job_name)
    sirs = get_sirs_by_tag(job_name)
    puts "terminating spot requests for " + job_name
    $log.info("terminating spot requests for " + job_name)
    cancel_spot_requests(sirs)
    puts "terminating instances for " + job_name
    $log.info("terminating instances for " + job_name)
    terminate_instances(ids)
end

def kill_all()
    job_name = "delayed_job::"
    ids = get_ids_by_tag(job_name)
    sirs = get_sirs_by_tag(job_name)
    puts "terminating spot requests for " + job_name
    $log.info("terminating spot requests for " + job_name)
    cancel_spot_requests(sirs)
    puts "terminating instances for " + job_name
    $log.info("terminating instances for " + job_name)
    terminate_instances(ids)
end

def count_delayed_job_nodes()
    cmd = "ec2-describe-instances  | grep delayed_job:: | wc -l"
    count = `#{cmd}`
    return count
end

## send email
def send_email(from, from_alias, to, to_alias, subject, message)
	msg = <<END_OF_MESSAGE
From: #{from_alias} <#{from}>
To: #{to_alias} <#{to}>
Subject: #{subject}

#{message}
END_OF_MESSAGE
	
	Net::SMTP.start('localhost') do |smtp|
		smtp.send_message msg, from, to
	end
end
## end of send email

if action == "launch"
    launch_instances(ami,instancesize,group,numberofinstances,os,job_name,job_count)
	message = "number of instances=" + numberofinstances + "||job_name=" + job_name
    send_email(from, from_alias, to, to_alias, subject, message)
end

if action == "terminate"
    puts "Terminating instances"
    $log.info("Terminating instances")
    terminate(job_name)
end

if action == "kill-all"
    count = count_delayed_job_nodes()
	if count.to_i > 0
    		puts "Terminating all instances"
    		$log.info("Terminating all instances")
    		kill_all()
	else
		puts " there are no running delayed_job nodes, exiting"
		$log.info(" there are no running delayed_job nodes, exiting")
		exit 0
	end
end
