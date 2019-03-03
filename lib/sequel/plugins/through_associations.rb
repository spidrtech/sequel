module Sequel
  module Plugins
    module ThroughAssociations

      ASSOCIATION_THROUGH_TYPES = {
        :one_to_many => :one_through_many,
        :many_to_one => :one_through_many,
        :many_to_many => :many_through_many
        # one_to_one
        # many_to_pg_array
        # pg_array_to_many
      }

      class MissingAssociation < Error; end
      class NoAssociationPath < Error; end

      # Ensure associations are loaded
      def self.apply mod
        mod.plugin(:associations)
      end

      module InstanceMethods

        def associate(type, name, opts = OPTS, &block)

          # Handle associations that are based on others
          if opts[:through] && !type.to_s.include?("_through_")
            return associate_through(type, name, opts, &block)
          end

          super

        end

        # Associates a related model with the current model using another association
        # as the intermediary.
        def associate_through(type, name, opts, &block)
          raise(Error, "#{type} does not support through associations") unless assoc_type = Sequel.synchronize{ASSOCIATION_THROUGH_TYPES[type]}

          result = find_association_path(**opts, name: name, models: self, from_through: true)

          # Remove the last table if it matches the destination table
          dest_model = result[:models].pop
          result[:tables].pop if result[:tables].last == dest_model.table_name

          # Build the association path
          path = []
          left_key = result[:keys].shift
          result[:tables].each do |table|
            path.push([table, result[:keys].shift, result[:keys].shift])
          end

          # Create the association
          if assoc_type.to_s.ends_with? "_through_many"
            # *_through_many has a path argument
            self.send(assoc_type,
              name,
              path,
              left_primary_key: left_key,
              right_primary_key: result[:keys].shift,
              class: dest_model,
              **opts,
              originally_through: opts[:through],
              &block
            )
          else
            # *_through_one does not have a path argument
            self.send(assoc_type,
              name,
              left_primary_key: left_key,
              right_primary_key: result[:keys].shift,
              class: dest_model,
              **opts,
              originally_through: opts[:through],
              &block
            )
          end
        end

        # Recurses through associations until a path to the destination is completed
        def find_association_path opts

          # Initialize arguments
          [:tables, :keys, :through, :models, :assocs].each do |k|
            opts[k] ||= []
            opts[k] = [opts[k]] unless Array === opts[k]
            opts[k] = opts[k].dup
          end

          # Find the linked association
          assoc = \
            opts[:models].last.association_reflection(opts[:through].last.to_s.pluralize.to_sym) \
            || opts[:models].last.association_reflection(opts[:through].last.to_s.singularize.to_sym)

          # Short circuit if association does not exist
          unless assoc

            #puts "#{"\t" * $tabs}" + opts[:models].inspect.red
            #puts "#{"\t" * $tabs}" + opts[:models].last.associations.inspect.yellow

            # Determine if finished or if the last relation is missing
            if opts[:from_through]

              m = opts[:models].pop
              t = opts[:through].pop
              path = [m]

              opts[:models].zip(opts[:through]).each do |model, through|
                path.push("#{model}.#{through}")
              end

              raise(MissingAssociation, "#{m} is missing through association :#{t} from #{path.join " -> "}")

            else

              if opts[:assocs].last[:name].to_s.singularize != (opts[:using] || opts[:name]).to_s.singularize
                text = "#{opts[:models].first}.#{opts[:name]} could not be resolved through path #{opts[:models].zip(opts[:through]).map{|model, through| "#{model}.#{through}"}.join " -> "}"
                raise(MissingAssociation, text)
              end

              return opts

            end

          end

          # Store the association
          opts[:assocs].push(assoc)

          # Handle *_through_many associations
          if assoc[:type].to_s.ends_with?("_through_many")

            opts[:through].push(assoc[:originally_through])
            opts[:from_through] = true

            # Search through the existing model first, falling back to the associated model
            search = [
              opts[:models].last,
              assoc[:class] || assoc[:class_name].constantize
            ]
            return begin
              model = search.shift
              raise(NoAssociationPath, opts) unless model
              self.find_association_path(**opts, models: opts[:models] + [model])
            rescue MissingAssociation
              # Try the next model in the search path
              # puts "#{"\t" * $tabs}retrying..."
              retry
            end

          end

          # Move to the new model
          opts[:models].push(assoc[:class] || assoc[:class_name].constantize)

          # Read the through association if present
          if assoc[:through]
            opts[:through].push(assoc[:using] || assoc[:through])
            opts[:from_through] = true
            opts[:using] = nil
            return self.find_association_path(**opts)
          end

          # Otherwise, add the new table to the stack
          if opts[:from_through] && opts[:models].last.respond_to?(:cti_tables)
            opts[:tables].push(opts[:models].last.cti_tables.first)
          else
            opts[:tables].push(opts[:models].last.table_name)
          end

          # Left side
          case assoc[:type]
            when :one_to_many, :one_to_one # 1:_
              opts[:keys].push(assoc.primary_key)
            when :many_to_one # n:_
              opts[:keys].push(assoc[:key])
            else
              raise
          end

          # Right side
          case assoc[:type]
            when :many_to_one, :one_to_one # _:1
              opts[:keys].push(assoc.primary_key)
            when :one_to_many # _:n
              opts[:keys].push(assoc[:key])
            else
              raise
          end

          # Check for a source association
          opts[:through].push(opts[:using] || opts[:name])
          opts[:from_through] = false
          return self.find_association_path(**opts)

        end


      end

    end
  end
end
