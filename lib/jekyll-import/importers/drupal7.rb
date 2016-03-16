module JekyllImport
  module Importers
    class Drupal7 < Importer
      # Reads a MySQL database via Sequel and creates a post file for each story
      # and blog node.
      MENU_QUERY = "SELECT n.title, \
                      n.nid, \
                      ml.mlid, \
                      ml.plid \
               FROM node AS n, \
                    menu_links AS ml \
               WHERE (%types%) \
               AND substr(link_path, locate('/',link_path)+1) = n.nid"

      QUERY = "SELECT n.title, \
                      fdb.body_value, \
                      fdb.body_summary, \
                      n.created, \
                      n.status, \
                      n.nid, \
                      u.name, \
                      ml.link_title, \
                      ml.mlid, \
                      ml.plid \
               FROM node AS n, \
                    field_data_body AS fdb, \
                    users AS u,
                    menu_links AS ml \
               WHERE (%types%) \
               AND n.nid = fdb.entity_id \
               AND n.vid = fdb.revision_id \
               AND n.uid = u.uid \
               AND substr(link_path, locate('/',link_path)+1) = n.nid"

      def self.validate(options)
        %w[dbname user].each do |option|
          if options[option].nil?
            abort "Missing mandatory option --#{option}."
          end
        end
      end

      def self.specify_options(c)
        c.option 'dbname', '--dbname DB', 'Database name'
        c.option 'user', '--user USER', 'Database user name'
        c.option 'password', '--password PW', 'Database user\'s password (default: "")'
        c.option 'host', '--host HOST', 'Database host name (default: "localhost")'
        c.option 'prefix', '--prefix PREFIX', 'Table prefix name'
        c.option 'types', '--types TYPE1[,TYPE2[,TYPE3...]]', Array, 'The Drupal content types to be imported.'
      end

      def self.require_deps
        JekyllImport.require_with_fallback(%w[
          rubygems
          sequel
          fileutils
          safe_yaml
        ])
      end

      def self.title_to_slug(title)
        title.strip.downcase.gsub(/(&|&amp;)/, ' and ').gsub(/[\s\.\/\\]/, '-').gsub(/[^\w-]/, '').gsub(/[-_]{2,}/, '-').gsub(/^[-_]/, '').gsub(/[-_]$/, '')
      end

      def self.menu_path(nav, mlid)
        path = ""
        while nav[mlid][:plid] != 0
          mlid = nav[mlid][:plid]
          path = "/" + nav[mlid][:slug] + path
        end
        path
      end

      def self.process(options)
        dbname = options.fetch('dbname')
        user   = options.fetch('user')
        pass   = options.fetch('password', "")
        host   = options.fetch('host', "localhost")
        prefix = options.fetch('prefix', "")
        types  = options.fetch('types', ['blog', 'story', 'article'])

        db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :encoding => 'utf8')

        unless prefix.empty?
          MENU_QUERY[" node "] = " " + prefix + "node "
          MENU_QUERY[" field_data_body "] = " " + prefix + "field_data_body "
          MENU_QUERY[" users "] = " " + prefix + "users "
          QUERY[" node "] = " " + prefix + "node "
          QUERY[" field_data_body "] = " " + prefix + "field_data_body "
          QUERY[" users "] = " " + prefix + "users "
        end

        types = types.join("' OR n.type = '")
        MENU_QUERY[" WHERE (%types%) "] = " WHERE (n.type = '#{types}') "
        QUERY[" WHERE (%types%) "] = " WHERE (n.type = '#{types}') "

        FileUtils.mkdir_p "_posts"
        FileUtils.mkdir_p "_drafts"
        FileUtils.mkdir_p "_layouts"


        # pass 1: get nav hierarchy
        nav = Hash.new
        db[MENU_QUERY].each do |post|
          title = post[:title]
          slug = title_to_slug(title)
          nav[post[:mlid]] = { :plid => post[:plid], :slug => slug }
        end

        # pass 2: fill out the articles
        db[QUERY].each do |post|
          # Get required fields and construct Jekyll compatible name
          post_title = post[:title]
          menu_title = post[:link_title]

          content = post[:body_value]
          summary = post[:body_summary]
          created = post[:created]
          author = post[:name]

          nid = post[:nid]
          plid = post[:plid]
          mlid = post[:mlid]

          time = Time.at(created)
          is_published = post[:status] == 1

          dir = is_published ? "_posts" : "_drafts"
          dir += menu_path(nav, mlid)
          FileUtils.mkdir_p dir

          slug = title_to_slug(post_title)
          name = slug + '.md'

          # Get the relevant fields as a hash, delete empty fields and convert
          # to YAML for the header
          data = {
            'layout' => 'post',
            'title' => post_title.strip.force_encoding("UTF-8"),
            'menu_title' => menu_title.strip.force_encoding("UTF-8"),
            'author' => author,
            'nid' => nid,
            'mlid' => mlid,
            'plid' => plid,
            'created' => created,
            'excerpt' => summary
          }.delete_if { |k,v| v.nil? || v == ''}.to_yaml

          # Write out the data and content to file
          File.open("#{dir}/#{name}", "w") do |f|
            f.puts data
            f.puts "---"
            f.puts content
          end

        end

        # TODO: Make dirs & files for nodes of type 'page'
          # Make refresh pages for these as well

        # TODO: Make refresh dirs & files according to entries in url_alias table
      end
    end
  end
end
