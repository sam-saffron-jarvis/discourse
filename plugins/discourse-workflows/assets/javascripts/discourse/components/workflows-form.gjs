import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import DecoratedHtml from "discourse/components/decorated-html";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import autoFocus from "discourse/modifiers/auto-focus";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

function isFormKitType(field, type) {
  return field.type === type;
}

function fieldOptions(field) {
  return field.options || [];
}

function responseErrorMessage(responseJSON) {
  return responseJSON?.error || i18n("discourse_workflows.form.error_message");
}

export default class WorkflowsForm extends Component {
  @service messageBus;

  @tracked state = "form";
  @tracked errorMessage = null;
  @tracked completionData = null;
  @tracked formSchemaOverride = null;
  channel = null;
  pendingFormWaitingUrl = null;

  willDestroy() {
    super.willDestroy(...arguments);
    this.#unsubscribe();
  }

  get formSchema() {
    return this.formSchemaOverride ?? this.args.model;
  }

  set formSchema(value) {
    this.formSchemaOverride = value;
  }

  @cached
  get formKitSchema() {
    return this.formSchema.form_kit_schema;
  }

  @cached
  get formData() {
    return this.formKitSchema?.data || {};
  }

  @cached
  get fields() {
    return (this.formKitSchema?.fields || []).map((field, index) => {
      if (field.type === "html") {
        return {
          ...field,
          html: trustHTML(field.html || ""),
          autofocus: index === 0,
        };
      }

      return {
        ...field,
        autofocus: index === 0,
      };
    });
  }

  @cached
  get completionHtml() {
    const completion = this.completionData || {};

    return {
      completion_title: trustHTML(completion.completion_title || ""),
      completion_message: trustHTML(completion.completion_message || ""),
      completion_text: trustHTML(completion.completion_text || ""),
    };
  }

  @action
  async handleSubmit(formData) {
    this.state = "submitting";

    try {
      const payload = { form_data: formData };
      const submitUrl =
        this.formSchema.form_submit_url ||
        `/workflows/form/${this.args.model.uuid}.json`;

      if (!this.formSchema.form_submit_url && this.args.model.resume_token) {
        payload.resume_token = this.args.model.resume_token;
      }

      const result = await ajax(submitUrl, {
        type: "POST",
        data: payload,
      });

      this.#handleSubmissionResult(result);
    } catch (e) {
      this.state = "error";
      this.errorMessage = responseErrorMessage(e?.jqXHR?.responseJSON);
    }
  }

  #handleSubmissionResult(result) {
    if (!result) {
      this.#complete();
      return;
    }

    if (result.status === "error") {
      this.state = "error";
      this.errorMessage = responseErrorMessage(result);
      return;
    }

    if (result.form_channel && result.form_waiting_url) {
      this.state = "waiting";
      this.pendingFormWaitingUrl = result.form_waiting_url;
      this.#subscribe(result.form_channel);
      return;
    }

    if (result.form_waiting_url) {
      this.#loadWaitingForm(result.form_waiting_url);
      return;
    }

    this.#complete(result.form_completion);
  }

  #subscribe(channel) {
    this.#unsubscribe();
    this.channel = channel;
    this.messageBus.subscribe(
      this.channel,
      (message) => {
        this.#handleMessage(message);
      },
      0
    );
  }

  #unsubscribe() {
    if (this.channel) {
      this.messageBus.unsubscribe(this.channel);
      this.channel = null;
    }
  }

  async #handleMessage(message) {
    if (message.status === "waiting_for_form") {
      await this.#loadWaitingForm(
        message.form_waiting_url || this.pendingFormWaitingUrl
      );
    } else if (message.status === "error") {
      this.#unsubscribe();
      this.state = "error";
      this.errorMessage = responseErrorMessage(message);
    }
  }

  async #loadWaitingForm(url) {
    if (!url) {
      this.state = "error";
      this.errorMessage = i18n("discourse_workflows.form.error_message");
      return;
    }

    try {
      const schema = await ajax(url);
      this.formSchema = schema;
      this.state = "form";
      this.pendingFormWaitingUrl = null;
      this.#unsubscribe();
    } catch {
      this.state = "error";
      this.errorMessage = i18n("discourse_workflows.form.error_message");
    }
  }

  #complete(completion) {
    this.#unsubscribe();

    if (completion?.on_submission === "redirect" && completion.redirect_url) {
      const url = completion.redirect_url;
      try {
        if (url.startsWith("/") && !url.startsWith("//")) {
          window.location.href = url;
        } else {
          const parsed = new URL(url);
          if (parsed.origin === window.location.origin) {
            window.location.href = url;
          }
        }
      } catch {
        // invalid URL, don't redirect
      }
      return;
    }

    this.completionData = completion || null;
    this.state = "complete";
  }

  <template>
    <div class="workflows-form">
      {{#if (eq this.state "form")}}
        <div class="workflows-form__header">
          {{#if this.formSchema.form_title}}
            <h1
              class="workflows-form__title"
            >{{this.formSchema.form_title}}</h1>
          {{/if}}
          {{#if this.formSchema.form_description}}
            <p
              class="workflows-form__description"
            >{{this.formSchema.form_description}}</p>
          {{/if}}
        </div>

        <Form @data={{this.formData}} @onSubmit={{this.handleSubmit}} as |form|>
          {{#each this.fields as |field|}}
            {{#if (isFormKitType field "html")}}
              <DecoratedHtml
                @html={{field.html}}
                @className="workflows-form__html"
              />
            {{else if (isFormKitType field "checkbox")}}
              <form.Field
                @type="checkbox"
                @name={{field.name}}
                @title={{field.title}}
                @description={{field.description}}
                @format="full"
                as |f|
              >
                <f.Control {{(if field.autofocus (modifier autoFocus))}} />
              </form.Field>
            {{else if (isFormKitType field "textarea")}}
              <form.Field
                @type="textarea"
                @name={{field.name}}
                @title={{field.title}}
                @description={{field.description}}
                @format="full"
                @validation={{field.validation}}
                @placeholder={{field.placeholder}}
                as |f|
              >
                <f.Control
                  placeholder={{field.placeholder}}
                  {{(if field.autofocus (modifier autoFocus))}}
                />
              </form.Field>
            {{else if (isFormKitType field "select")}}
              <form.Field
                @type="select"
                @name={{field.name}}
                @title={{field.title}}
                @description={{field.description}}
                @format="full"
                @validation={{field.validation}}
                as |f|
              >
                <f.Control {{(if field.autofocus (modifier autoFocus))}} as |c|>
                  {{#each (fieldOptions field) as |opt|}}
                    <c.Option @value={{opt.value}}>{{opt.label}}</c.Option>
                  {{/each}}
                </f.Control>
              </form.Field>
            {{else if (isFormKitType field "radio-group")}}
              <form.Field
                @type="radio-group"
                @name={{field.name}}
                @title={{field.title}}
                @description={{field.description}}
                @format="full"
                @validation={{field.validation}}
                as |f|
              >
                <f.Control
                  {{(if field.autofocus (modifier autoFocus))}}
                  as |RadioGroup|
                >
                  {{#each (fieldOptions field) as |opt|}}
                    <RadioGroup.Radio
                      @value={{opt.value}}
                    >{{opt.label}}</RadioGroup.Radio>
                  {{/each}}
                </f.Control>
              </form.Field>
            {{else}}
              <form.Field
                @type={{field.type}}
                @name={{field.name}}
                @title={{field.title}}
                @description={{field.description}}
                @format="full"
                @validation={{field.validation}}
                @placeholder={{field.placeholder}}
                as |f|
              >
                <f.Control
                  placeholder={{field.placeholder}}
                  {{(if field.autofocus (modifier autoFocus))}}
                />
              </form.Field>
            {{/if}}
          {{/each}}

          <form.Submit @label="discourse_workflows.form.submit" />
        </Form>
      {{else if (eq this.state "submitting")}}
        <ConditionalLoadingSpinner @condition={{true}} />
      {{else if (eq this.state "waiting")}}
        <ConditionalLoadingSpinner @condition={{true}} />
      {{else if (eq this.state "complete")}}
        <div class="workflows-form__complete">
          {{#if this.completionData}}
            {{#if (eq this.completionData.on_submission "redirect")}}
              <p>{{i18n "discourse_workflows.form.redirecting"}}</p>
            {{else if (eq this.completionData.on_submission "show_text")}}
              <DecoratedHtml
                @html={{this.completionHtml.completion_text}}
                @className="workflows-form__completion-text"
              />
            {{else}}
              {{#if this.completionData.completion_title}}
                <DecoratedHtml
                  @html={{this.completionHtml.completion_title}}
                  @className="workflows-form__completion-title"
                />
              {{/if}}
              {{#if this.completionData.completion_message}}
                <DecoratedHtml
                  @html={{this.completionHtml.completion_message}}
                  @className="workflows-form__completion-message"
                />
              {{else}}
                <p>{{i18n "discourse_workflows.form.thank_you"}}</p>
              {{/if}}
            {{/if}}
          {{else}}
            <p>{{i18n "discourse_workflows.form.thank_you"}}</p>
          {{/if}}
        </div>
      {{else if (eq this.state "error")}}
        <div class="workflows-form__error">
          <p>{{this.errorMessage}}</p>
        </div>
      {{/if}}
    </div>
  </template>
}
