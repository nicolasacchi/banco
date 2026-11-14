module Api
  module V1
    # The teacher's pages as JSON (D-328), read-only, for every token role: the home dashboard, a subject's course path, one
    # topic, the entry test. They answer with the facts of Teacher::Home|Dashboard, CourseReview, TopicReview and TestReview
    # (Teacher::ApiView); opening a page for the teacher records "read" events, and these never do, so a read here can never
    # stand in for the teacher reading (the gate of approve_topic still asks for the page in the browser, or the console's attestation).
    class TeacherViewsController < Api::BaseController
      before_action :load_subject, except: :home

      # GET /api/v1/teacher/home?student=KEY
      def home
        key = params[:student].to_s
        student = key.empty? ? Student.official : Student.find_by(key: key, kind: "student")
        return refuse("E-NOT-FOUND", "student", "no student #{key.first(40).inspect}", "banco teacher home", 404) if !key.empty? && (!Student::KEY_FORMAT.match?(key) || student.nil?)

        render json: Teacher::ApiView.home(Teacher::Dashboard.new(student: student))
      end

      # GET /api/v1/teacher/subjects/:key/course?only=ready
      def course
        render json: Teacher::ApiView.course(Teacher::CourseReview.new(@subject), only_ready: params[:only] == "ready")
      end

      # GET /api/v1/teacher/subjects/:key/topics/:topic?lesson=full
      def topic
        review = Teacher::TopicReview.new(@subject, params[:topic].to_s)
        return refuse("E-NOT-FOUND", "topic", "#{params[:topic]} is not a topic of #{@subject.key}", "banco teacher course #{@subject.key}", 404) unless review.present?

        render json: Teacher::ApiView.topic(review, lesson_text: params[:lesson] == "full")
      end

      # GET /api/v1/teacher/subjects/:key/test
      def test
        render json: Teacher::ApiView.test(Teacher::TestReview.new(@subject))
      end

      private

      def load_subject
        @subject = Subject.find_by(key: params[:key].to_s)
        refuse("E-NOT-FOUND", "subject", "no subject #{params[:key].to_s.first(40).inspect}", "banco status", 404) unless @subject
      end
    end
  end
end
