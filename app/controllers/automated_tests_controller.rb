# The actions necessary for managing the Testing Framework form
require 'helpers/ensure_config_helper.rb'

class AutomatedTestsController < ApplicationController
  include AutomatedTestsHelper

  before_filter      :authorize_only_for_admin,
                     :only => [:manage, :update, :download]
  before_filter      :authorize_for_student,
                     only: [:student_interface]

  # Update is called when files are added to the assigment
  def update
    @assignment = Assignment.find(params[:assignment_id])

    create_test_repo(@assignment)

    # Perform transaction, if errors, none of new config saved
    @assignment.transaction do
      # Get new script from upload form
      new_script = params[:new_script]
      # Get new support file from upload form
      new_support_file = params[:new_support_file]

      @assignment = process_test_form(@assignment,
                                      assignment_params,
                                      new_script,
                                      new_support_file)
      # Save assignment and associated test files
      if @assignment.save
        flash[:success] = I18n.t("assignment.update_success")
        unless new_script.nil?
          assignment_tests_path = File.join(
            MarkusConfigurator.markus_config_automated_tests_repository,
            @assignment.repository_folder,
            new_script.original_filename)
          File.open(assignment_tests_path, 'w') { |f| f.write new_script.read }
        end

        unless new_support_file.nil?
          assignment_tests_path = File.join(
            MarkusConfigurator.markus_config_automated_tests_repository,
            @assignment.repository_folder,
            new_support_file.original_filename)
          File.open(
            assignment_tests_path, 'w') { |f| f.write new_support_file.read }
        end
        redirect_to :action => 'manage',
                    :assignment_id => params[:assignment_id]
      else
        render :manage
      end

    end
  end

  # Manage is called when the Automated Test UI is loaded
  def manage
    @assignment = Assignment.find(params[:assignment_id])
    @assignment.test_scripts.build
    @assignment.test_support_files.build
  end


  def student_interface
    @assignment = Assignment.find(params[:id])
    @student = current_user
    @grouping = @student.accepted_grouping_for(@assignment.id)

    unless @grouping.nil?
      @test_script_results = TestScriptResult.where(grouping: @grouping)
                                       .order(created_at: :desc)
      @token = fetch_latest_tokens_for_grouping(@grouping)
    end
  end

  def execute_test_run
    assignment = Assignment.find(params[:id])
    grouping = current_user.accepted_grouping_for(assignment.id)
    token = fetch_latest_tokens_for_grouping(grouping)

    # For running tests
    if (token && token.tokens > 0) || assignment.unlimited_tokens
      test_errors = run_tests(grouping.id)
      if test_errors.nil?
        flash_message(:notice, I18n.t('automated_tests.tests_running'))
      else
        flash_message(:error, test_errors)
      end
    end
    redirect_to action: :student_interface
  end

  def run_tests(grouping_id)
    begin
      AutomatedTestsHelper.request_a_test_run(grouping_id, 'request', @current_user)
      return nil
    rescue Exception => e
      #TODO: really shouldn't be leaking error if student.
      return e.message
    end
  end

  # Download is called when an admin wants to download a test script
  # or test support file
  # Check three things:
  #  1. filename is in DB
  #  2. file is in the directory it's supposed to be
  #  3. file exists and is readable
  def download
    filedb = nil
    if params[:type] == 'script'
      filedb = TestScript.find_by_assignment_id_and_script_name(params[:assignment_id], params[:filename])
    elsif params[:type] == 'support'
      filedb = TestSupportFile.find_by_assignment_id_and_file_name(params[:assignment_id], params[:filename])
    end

    if filedb
      if params[:type] == 'script'
        filename = filedb.script_name
      elsif params[:type] == 'support'
        filename = filedb.file_name
      end
      assn_short_id = Assignment.find(params[:assignment_id]).short_identifier

      # the given file should be in this directory
      should_be_in = File.join(MarkusConfigurator.markus_config_automated_tests_repository, assn_short_id)
      should_be_in = File.expand_path(should_be_in)
      filename = File.expand_path(File.join(should_be_in, filename))

      if should_be_in == File.dirname(filename) and File.readable?(filename)
        # Everything looks OK. Send the file over to the client.
        file_contents = IO.read(filename)
        send_file filename,
                  :type => ( SubmissionFile.is_binary?(file_contents) ? 'application/octet-stream':'text/plain' ),
                  :x_sendfile => true

     # print flash error messages
      else
        flash[:error] = I18n.t('automated_tests.download_wrong_place_or_unreadable');
        redirect_to :action => 'manage'
      end
    else
      flash[:error] = I18n.t('automated_tests.download_not_in_db');
      redirect_to :action => 'manage'
    end
  end

  private

  def assignment_params
    params.require(:assignment)
        .permit(:enable_test,
                :assignment_id,
                :tokens_per_day,
                :unlimited_tokens,
                test_files_attributes:
                    [:id, :filename, :filetype, :is_private, :_destroy],
                test_scripts_attributes:
                    [:id, :assignment_id, :seq_num, :script_name, :description,
                     :max_marks, :run_on_submission, :run_on_request,
                     :halts_testing, :display_description, :display_run_status,
                     :display_marks_earned, :display_input,
                     :display_expected_output, :display_actual_output,
                     :_destroy],
                test_support_files_attributes:
                    [:id, :file_name, :assignment_id, :description, :_destroy])
  end
end
