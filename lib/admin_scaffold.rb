module AdministrateMe
  module AdminScaffold
    module InstanceMethods

      def get_list    
        session[:mini] = ''
        params[:search_key] ||= session["#{controller_name}_search_key"] if session["#{controller_name}_search_key"]
        @search_key = params[:search_key]
        get_records
        set_search_message
        session["#{controller_name}_search_key"] = @search_key
      end

      def get_records
        conditions = model_class.merge_conditions_backport(*[parent_scope, global_scope, search_scope, filter_scope])
        options = {:conditions => conditions, :include => get_includes, :order => get_order}
        if model_class.respond_to?('paginate')
          @records = model_class.paginate(options.merge(:page => params[:page], :per_page => get_per_page))
          @count_for_search = @records.total_entries
        else
          @records = model_class.find(:all, options)
          @count_for_search = @records.size
        end
      end

      def get_per_page
        options[:per_page] || 15
      end

      def get_includes
        options[:includes] || nil
      end

      def get_order
        options[:order_by] || nil
      end

      def get_list_options
        list_options = {}
        list_options[:per_page] = (options[:per_page]) ? options[:per_page] : 15
        list_options[:order]    = options[:order_by] rescue nil
        list_options
      end

      def set_search_message
        if options[:search] && !params[:search_key].blank?
          session[:mini] = "se encontraron #{@count_for_search} resultados con \"<b>#{@search_key}</b>\""
        end
      end

      def parent_scope
        parent = options[:parent]
        foreign_key = options[:foreign_key].blank? ? "#{options[:parent]}_id" : options[:foreign_key]
        if parent
          { foreign_key => params["#{parent}_id"] }
        end
      end

      def global_scope
        respond_to?('general_conditions') ? general_conditions : nil
      end   

      def search_scope
        !@search_key.blank? && options[:search] ? conditions_for(options[:search]) : nil
      end

      def filter_scope
        options[:filter_config] ? options[:filter_config].conditions_for_filter(params[:filter]) : nil
      end

      def index
        get_list
        call_before_render
        respond_to do |format|
          format.html { render :template => 'commons/index' }
          format.js   {
            render :update do |page|
              page.replace_html :list_area, :partial => 'list'
            end
          }
          format.xml  { render :xml => @records.to_xml }
        end
      end    

      def show
        if_available(:show) do 
          call_before_render
          respond_to do |format|
            format.html # show.rhtml
            format.xml  { render :xml => @resource.to_xml }      
          end
        end
      end

      def new    
        if_available(:new) do
          @resource = ( options[:model] ? options[:model] : controller_name ).classify.constantize.new
          call_before_render
          render :template => 'commons/base_form'
        end
      end

      def edit
        if_available(:edit) do
          call_before_render
          render :template => 'commons/base_form'
        end
      end

      def create
        if_available(:new) do
          create_params = params[model_name.to_sym]
          if parent = options[:parent]
            create_params[parent_key.to_sym] = @parent.id
          end
          @resource = model_class.new(create_params)
          save_model
          call_before_render
          respond_to do |format|
            if @success
              flash[:notice] = 'El registro fue creado exitosamente'
              session["#{controller_name}_search_key"] = nil
              format.html { redirect_to path_to_index }
              format.xml  { head :created, :location => eval("#{controller_name.singularize}_url(@resource)") }
            else
              format.html { render :template => "commons/base_form" }
              format.xml  { render :xml => @resource.errors.to_xml }        
            end
          end
        end
      end

      def update 
        if_available(:edit) do 
          @resource.attributes = params[model_name.to_sym]
          save_model
          call_before_render
          respond_to do |format|
            if @success
              flash[:notice] = 'Los cambios fueron guardados exitosamente'
              format.html { redirect_to path_to_element(@resource) }
              format.xml  { head :ok }
            else
              format.html { render :template => "commons/base_form" }
              format.xml  { render :xml => @resource.errors.to_xml }
            end
          end
        end
      end

      def destroy
        if_available(:destroy) do
          @resource.destroy
          call_before_render
          respond_to do |format|
            flash[:notice] = 'El registro fue eliminado exitosamente.'
            format.html { redirect_to path_to_index }      
            format.xml  { head :ok }
          end
        end
      end

      #FIXME: I need some testing!
      def path_to_index(*args)
        local_options = args.last.is_a?(Hash) ? args.pop : nil
        prefix  = args.first
        parts = []
        # add prefix
        parts << prefix if prefix
        nspace = self.class.namespace
        # add namespace
        parts << nspace if nspace
        # add parent
        parent = options[:parent]
        parts << options[:parent] unless parent.blank?
        # add controller
        cname = prefix ? controller_name.singularize : controller_name
        parts << cname
        #
        parts << 'path'
        helper_name = parts.join('_')
        parameters = []
        parameters << params[:"#{parent}_id"] unless parent.blank?
        parameters << local_options if local_options
        send(helper_name, *parameters)
      end

      def path_to_element(element, options = {})
        options[:parent] ||= self.options[:parent]
        create_path(self.controller_name.singularize, element, self.class.namespace, @parent, options)
      end
      
      def get_index
        path  = "#{controller_name}_path"
        unless options[:parent].blank?
          path << "(params[:#{options[:parent].to_s}_id])"
        end     
        eval(path)
      end

      def get_resource
        @resource = model_class.find(params[:id])
      end   

      def model_name
        self.class.model_name
      end

      def model_class
        self.class.model_class
      end

      def options
        self.class.options
      end

      def parent_class
        self.class.parent_class
      end

      def parent_key
        options[:foreign_key] || "#{options[:parent]}_id".to_sym
      end

      def conditions_for(fields=[])
        predicate = []
        values    = []
        fields.each do |field|
          predicate << "lower(#{field.to_s}) like ?"
          values    << "'%' + @search_key.downcase + '%'"
        end
        eval("[\"#{predicate.join(' OR ')}\", #{values.join(',')}]")
      end

      protected

        def if_available(action)
          if self.class.accepted_action?(action)
            yield
          else
            raise ActionController::UnknownAction
          end
        end

        def save_model
          begin
            model_class.transaction do 
              before_save if respond_to?('before_save')
              if @success = @resource.save!
                after_save if respond_to?('after_save')
              end
            end 
          rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordInvalid
            logger.error("Ocurrió una exception al salvar el registro: " + $!)
            @success = false
          end
        end

        def get_parent
          if parent = options[:parent]
            begin
              @parent = parent_class.find(params[:"#{parent}_id"])
            rescue ActiveRecord::RecordNotFound
              flash[:error] = "No existe el padre del elemento solicitado"
              redirect_to ''
              return false
            end
          end
        end

        def generate_url
          html  = "url("
          unless options[:parent].blank?
            html << "@resource.send(:#{options[:parent]}_id), "
          end
          html << "@resource)"
          html
        end            

        def call_before_render
          before_render if respond_to?('before_render')
        end
        
    end
  end
  
  module InstanceMethods
    
    def create_path(controller_name, element, namespace, parent, options = {})
      parts = []
      # add prefix
      parts << options[:prefix] if options[:prefix]
      # add namespace
      parts << namespace if namespace
      # add parent
      parts << options[:parent] if options[:parent]
      # add controller
      parts << controller_name
      #
      parts << 'path'
      helper_name = parts.join('_')
      ids = [element]
      ids.unshift parent unless parent.blank?
      send(helper_name, *ids)
    end

  end
end
