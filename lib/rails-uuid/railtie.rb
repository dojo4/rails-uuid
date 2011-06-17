module RailsUUID  
  class Railtie < Rails::Railtie
  ##
  # the adapter is not loaded until a connection is actually established, so
  # we can't mangle NATIVE_DATABASE_TYPES until the end of initialization The
  # values from it should be read DURING the migarion process, so it should
  # still work.
  #

  ##
  # Rails.application.config.active_record.schema_format = :sql
  #

  if defined?(Rake)
    extend Rake::DSL if defined?(Rake::DSL)

    module_eval <<-__, __FILE__, __LINE__

      namespace(:db) do
        namespace(:schema) do
          task(:dump => :environment) do
          end
        end
      end

    __
  end

  config.after_initialize do

  ##
  # grab the database configuration
  #
    spec = Rails.configuration.database_configuration[Rails.env].to_options!
    adapter = spec[:adapter]

    raise("DB Adapter is not supported by rails-uuid gem") unless UUID_DB_PK_TYPE.has_key?(adapter)

  ##
  # force the adapter to load, tracking loaded connection adapters
  #
    before_adapter_classes = ActiveRecord::ConnectionAdapters::AbstractAdapter.subclasses
    before_column_classes = ActiveRecord::ConnectionAdapters::Column.subclasses

    begin
      require "active_record/connection_adapters/#{ adapter }_adapter"
    rescue LoadError => e
      raise "Please install the #{ adapter } adapter: `gem install activerecord-#{ adapter }-adapter` (#{e})"
    end

    after_adapter_classes = ActiveRecord::ConnectionAdapters::AbstractAdapter.subclasses
    after_column_classes = ActiveRecord::ConnectionAdapters::Column.subclasses

  ##
  # determine the specific classes we are going to hack the shit out of
  #
    adapter_class =
      (before_adapter_classes - after_adapter_classes).last ||
      ActiveRecord::ConnectionAdapters::AbstractAdapter.subclasses.last

    column_class =
      (before_column_classes - after_column_classes).last ||
      ActiveRecord::ConnectionAdapters::Column.subclasses.last


  ##
  # mixin the monkey patches into the right places
  #
    ActiveRecord::Base.send(:include, RailsUUID::ActiveRecordUUID)

    ActiveRecord::ConnectionAdapters::TableDefinition.send(:include, RailsUUID::TableDefinitionUUID)

    adapter_class.send(:include, RailsUUID::AdapterUUID)

  ## 
  # hack the shit out of the adapter to be uuid aware for queries (find) and
  # ddl (rake/migrations) actions 
  #
    adapter_class.module_eval do

    ##
    # handle quoting uuids.  hack an invalid uuid to force ar to throw
    # record_not_found
    #
      alias_method('__quote__', 'quote') unless method_defined?('__quote__')
      def quote(value, column = nil)
        return super unless column

        if column.type == :uuid && !value.blank?
          re = /^ [0-9a-zA-Z]{8} - [0-9a-zA-Z]{4} - [0-9a-zA-Z]{4} - [0-9a-zA-Z]{4} - [0-9a-zA-Z]{12} $/iox
          unless value.to_s =~ re
            value = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
          end
          return __quote__(value.to_s)
        end

        return __quote__(value, column)
      end

    ## 
    # these *required* for db:schema:dump and friends to work.  ar needs to
    # *know* about uuids as primary key
    #
      alias_method('__pk_and_sequence_for__', 'pk_and_sequence_for')
      def pk_and_sequence_for(table)
        result = __pk_and_sequence_for__(table)

        begin
          if result.nil? or result == [nil, nil]
            if columns(table).detect{|c| c.name.to_s == 'id' and c.type.to_s == 'uuid' }
              ['id', nil]
            else
              [nil, nil]
            end
          else
            result
          end
        rescue Object
         abort($!.to_s)
        end
      end

      alias_method('__primary_key__', 'primary_key')
      def primary_key(table)
        result = __primary_key__(table)

        begin
          if result.nil? or result == [nil, nil]
            if columns(table).detect{|c| c.name.to_s == 'id' and c.type.to_s == 'uuid' }
              'id'
            else
              nil
            end
          else
            result
          end
        rescue Object
         abort($!.to_s)
        end
      end
    end


    column_class.module_eval do
      def simplified_type_with_uuid(field_type)
        field_type.to_s == 'uuid' ? :uuid : simplified_type_without_uuid(field_type)
      end
      alias_method_chain(:simplified_type, :uuid)


=begin
      def type_cast_with_uuid(value)
      raise value.inspect
        return nil if value.nil?
        case type
          when :string
            case sql_type.to_s
            when /uuid/
            raise value.inspect
  #raise(({:value => value, :type => type, :sql_type => sql_type}.inspect))
            else
              value.to_s
            end
          else
            type_cast_without_uuid(value)
        end
      end
      alias_method_chain(:type_cast, :uuid)
=end

=begin
      def type_cast_with_uuid(value)
        return nil if value.nil?
        case type
          when :string
            case value
            else
              value.to_s
            end
          else
            type_cast_without_uuid(value)
        end
      end
      alias_method_chain(:type_cast, :uuid)
=end
    end
  end

  end
end
