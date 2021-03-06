module VagrantPlugins
  module MultiHostsUpdater
    module MultiHostsUpdater
      @@hosts_path = Vagrant::Util::Platform.windows? ? File.expand_path('system32/drivers/etc/hosts', ENV['windir']) : '/etc/hosts'

      def getIps
        ips = []
        if @machine.config.multihostsupdater.force_ips.is_a?(Array)
           return @machine.config.multihostsupdater.force_ips
        end
        @machine.config.vm.networks.each do |network|
          key, options = network[0], network[1]
          ip = options[:ip] if key == :private_network
          ips.push(ip) if ip
        end
        return ips
      end

      # Get hostnames by specific IP.
      # This option is only valid if a Hash is provided 
      # from the `config.multihostsupdater.aliases` parameter
      def getHostnames(ip=nil)
        hostnames = []
        if @machine.config.multihostsupdater.aliases.is_a?(Hash)
          hostnames = @machine.config.multihostsupdater.aliases[ip] || hostnames
        elsif @machine.config.multihostsupdater.aliases.is_a?(Array)
          hostnames = Array(@machine.config.vm.hostname) if !@machine.config.vm.hostname.nil?
          hostnames.concat(@machine.config.multihostsupdater.aliases)
        end

        return hostnames
      end

      def addHostEntries()
        ips = getIps
        file = File.open(@@hosts_path, "rb")
        hostsContents = file.read
        uuid = @machine.id
        name = @machine.name
        entries = []
        ips.each do |ip|
          hostnames = getHostnames(ip)
          hostEntries = getHostEntries(ip, hostnames, name, uuid)
          hostEntries.each do |hostEntry|
            escapedEntry = Regexp.quote(hostEntry)
            if !hostsContents.match(/#{escapedEntry}/)
              @ui.info "adding to (#@@hosts_path) : #{hostEntry}"
              entries.push(hostEntry)
            end
          end
        end
        addToHosts(entries)
      end

      def cacheHostEntries
        @machine.config.multihostsupdater.id = @machine.id
      end

      def removeHostEntries
        if !@machine.id and !@machine.config.multihostsupdater.id
          @ui.warn "No machine id, nothing removed from #@@hosts_path"
          return
        end
        file = File.open(@@hosts_path, "rb")
        hostsContents = file.read
        uuid = @machine.id || @machine.config.multihostsupdater.id
        hashedId = Digest::MD5.hexdigest(uuid)
        if hostsContents.match(/#{hashedId}/)
            removeFromHosts
        end
      end

      def host_entry(ip, hostnames, name, uuid = self.uuid)
        %Q(#{ip}  #{hostnames.join(' ')}  #{signature(name, uuid)})
      end

      def getHostEntries(ip, hostnames, name, uuid = self.uuid)
        entries = []
        hostnames.each do |hostname|
          entries.push(%Q(#{ip}  #{hostname}  #{signature(name, uuid)}))
        end
        return entries
      end

      def addToHosts(entries)
        return if entries.length == 0
        content = entries.join("\n").strip
        if !File.writable?(@@hosts_path)
          sudo(%Q(sh -c 'echo "#{content}" >> #@@hosts_path'))
        else
          content = "\n" + content
          hostsFile = File.open(@@hosts_path, "a")
          hostsFile.write(content)
          hostsFile.close()
        end
      end

      def removeFromHosts(options = {})
        uuid = @machine.id || @machine.config.multihostsupdater.id
        hashedId = Digest::MD5.hexdigest(uuid)
        if !File.writable?(@@hosts_path)
          sudo(%Q(sed -i -e '/#{hashedId}/ d' #@@hosts_path))
        else
          hosts = ""
          File.open(@@hosts_path).each do |line|
            hosts << line unless line.include?(hashedId)
          end
          hostsFile = File.open(@@hosts_path, "w")
          hostsFile.write(hosts)
          hostsFile.close()
        end
      end



      def signature(name, uuid = self.uuid)
        hashedId = Digest::MD5.hexdigest(uuid)
        %Q(# VAGRANT: #{hashedId} (#{name}) / #{uuid})
      end

      def sudo(command)
        return if !command
        if Vagrant::Util::Platform.windows?
          `#{command}`
        else
          `sudo #{command}`
        end
      end
    end
  end
end
