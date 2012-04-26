module Process
  def self.exists?(pid, partial_name=nil)
    Process.getpgid(pid.to_i)
    #puts "[Process.exists] pid exists: #{pid} (#{File.read("/proc/#{pid}/cmdline")[0..13]}) #{!partial_name || File.read("/proc/#{pid}/cmdline").include?(partial_name)}"
    !partial_name || File.read("/proc/#{pid}/cmdline").include?(partial_name)
  rescue Errno::ESRCH
    #puts "[Process.exists] Process no longer exists: #{pid}"
    false
  rescue Errno::EPERM => ex
    raise ex if !partial_name || File.read("/proc/#{pid}/cmdline").include?(partial_name)
    #puts "[Process.exists] EPERM while testing pid: #{pid}"
    false
  rescue Exception => ex
    puts "[Process.exists] #{ex.class}: #{ex.message}"
    raise ex
  end
end