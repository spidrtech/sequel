module Sequel
  module Plugins
    module CircularAssociationSolver

      # Ensure associations are loaded
      def self.apply mod
        mod.plugin(::Sequel::Model::Associations)
        mod.instance_eval do
          @_resolving = false
          @_resolver_stack = []
        end
      end

      module ClassMethods

        # Solves any remaining circular associations
        def solve_circular_associations!

          # Keep trying to solve as long as the stack length is reduced each time
          length = nil
          while length != @_resolver_stack.count do

            length = @_resolver_stack.count
            stack = @_resolver_stack

            # Attempt to solve remaining circular associations
            @_resolver_stack = []
            stack.each do |klass, assoc_type, name, opts, block|
              klass.send(assoc_type, name, **opts, &block)
            end

          end

          # Output errors for any unsolved associations
          @_resolving = true
          @_resolver_stack.each do |klass, assoc_type, name, opts, block|
            klass.send(assoc_type, name, **opts, &block)
          end
          @_resolving = false

        end

        def associate_through(type, name, opts, &block)
          begin
            result = super
          rescue Sequel::Model::Associations::MissingAssociation, Sequel::Model::Associations::NoAssociationPath => e

            # Re-raise if we were resolving
            raise e if @_resolving

            # Otherwise, attempt to resolve later
            unless result
              @_resolver_stack.push([self, type, name, opts, block])
              return
            end

          end
        end

      end
    end
  end
end
